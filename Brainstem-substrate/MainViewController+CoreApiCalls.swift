import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func fetchPrimitiveConstant(with path: ConstantCodingPath) throws -> JSON {
        guard let entry = runtimeMetadata!.getConstant(in: path.moduleName, constantName: path.constantName) else {
            throw NSError(domain: "Invalid storage path", code: 0)
        }

        do {
            let decoder = try DynamicScaleDecoder(data: entry.value, registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
            return try decoder.read(type: entry.type)
        } catch {
            throw error
        }
    }

    func fetchBlockHash(with blockNumber: BlockNumber) throws -> String {
        let operation = JSONRPCListOperation<String>(engine: engine!,
                                                      method: RPCMethod.getBlockHash,
                                                      parameters: [blockNumber.toHex()])

        OperationQueue().addOperations([operation], waitUntilFinished: true)

        do {
            return try operation.extractNoCancellableResultData()
        } catch {
            throw error
        }
    }

    func fetchAccountNonce(with accountAddress: String) throws -> UInt32 {
        let operation = JSONRPCListOperation<UInt32>(engine: engine!,
                                                     method: RPCMethod.getExtrinsicNonce,
                                                     parameters: [accountAddress])

        OperationQueue().addOperations([operation], waitUntilFinished: true)

        do {
            return try operation.extractNoCancellableResultData()
        } catch {
            throw error
        }
    }

    func fetchBlockNumber() throws -> BlockNumber {
        do {
            let finalizedBlockHashOperation: JSONRPCListOperation<String> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getFinalizedBlockHash
            )

            OperationQueue().addOperations([finalizedBlockHashOperation], waitUntilFinished: true)

            let blockHash = try finalizedBlockHashOperation.extractNoCancellableResultData()

            let finalizedHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getBlockHeader,
                parameters: [blockHash]
            )

            OperationQueue().addOperations([finalizedHeaderOperation], waitUntilFinished: true)

            let finalizedHeader = try finalizedHeaderOperation.extractNoCancellableResultData()

            let currentHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                engine: engine!,
                method: RPCMethod.getBlockHeader
            )

            OperationQueue().addOperations([currentHeaderOperation], waitUntilFinished: true)

            let header = try currentHeaderOperation.extractNoCancellableResultData()

            var bestHeader: Block.Header
            if !header.parentHash.isEmpty {
                let bestHeaderOperation: JSONRPCListOperation<Block.Header> = JSONRPCListOperation(
                    engine: engine!,
                    method: RPCMethod.getBlockHeader,
                    parameters: [header.parentHash]
                )

                OperationQueue().addOperations([bestHeaderOperation], waitUntilFinished: true)

                bestHeader = try bestHeaderOperation.extractNoCancellableResultData()
            } else {
                bestHeader = header
            }

            guard
                let bestNumber = BigUInt.fromHexString(bestHeader.number),
                let finalizedNumber = BigUInt.fromHexString(finalizedHeader.number),
                bestNumber >= finalizedNumber else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let blockNumber = bestNumber - finalizedNumber > Self.maxFinalityLag ? bestNumber : finalizedNumber

            return BlockNumber(blockNumber)
        } catch {
            throw error
        }
    }

    func executeMortalEraOperation() throws -> (BlockNumber, Era) {
        do {
            var path = ConstantCodingPath.blockHashCount
            let blockHashCountOperation: StringScaleMapper<BlockNumber> = try fetchPrimitiveConstant(with: path).map(to: StringScaleMapper<BlockNumber>.self)
            let blockHashCount = blockHashCountOperation.value ?? BlockNumber(Self.fallbackMaxHashCount)

            path = ConstantCodingPath.minimumPeriodBetweenBlocks
            let minimumPeriodOperation: StringScaleMapper<Moment> = try fetchPrimitiveConstant(with: path).map(to: StringScaleMapper<Moment>.self)
            let minimumPeriod = minimumPeriodOperation.value

            let blockTime = minimumPeriod ?? Moment(Self.fallbackPeriod)

            let unmappedPeriod = (Self.mortalPeriod / UInt64(blockTime)) + UInt64(Self.maxFinalityLag)

            let mortalLength = min(UInt64(blockHashCount), unmappedPeriod)

            let blockNumber = try fetchBlockNumber()

            let constrainedPeriod: UInt64 = min(1 << 16, max(4, mortalLength))
            var period: UInt64 = 1

            while period < constrainedPeriod {
                period = period << 1
            }

            let unquantizedPhase = UInt64(blockNumber) % period
            let quantizeFactor = max(period >> 12, 1)
            let phase = (unquantizedPhase / quantizeFactor) * quantizeFactor

            let eraBlockNumber = ((UInt64(blockNumber) - phase) / period) * period + phase
            return (BlockNumber(eraBlockNumber), Era.mortal(period: period, phase: phase))
        } catch {
            throw error
        }
    }

    func generateRuntimeCall(didAccountAddress: String, didName: String, didValue: String) throws -> RuntimeCall<GenerateDidCall> {
        do {
            let didAccountId = try SS58AddressFactory().accountId(from: didAccountAddress)

            let didNameData = didName.data(using: .utf8)!
            let didValueData = didValue.data(using: .utf8)!

            let args = GenerateDidCall(did_account: didAccountId, name: didNameData, value: didValueData, valid_for: nil)

            return RuntimeCall<GenerateDidCall>(
                moduleName: "PeaqDid",
                callName: "add_attribute",
                args: args
            )
        } catch {
            throw error
        }
    }

    func getAccountBalance(accountAddress: String) throws -> AccountInfo? {
        do {
            let accountId = try! SS58AddressFactory().accountId(from: accountAddress)
            let keyParams = [accountId]

            let path = StorageCodingPath.account
            guard let entry = runtimeMetadata!.getStorageMetadata(
                in: path.moduleName,
                storageName: path.itemName
            ) else {
                throw NSError(domain: "Invalid storage path", code: 0)
            }

            let keyType: String
            let hasher: StorageHasher

            switch entry.type {
            case let .map(mapEntry):
                keyType = mapEntry.key
                hasher = mapEntry.hasher
            case let .doubleMap(doubleMapEntry):
                keyType = doubleMapEntry.key1
                hasher = doubleMapEntry.hasher
            case let .nMap(nMapEntry):
                guard
                    let firstKey = nMapEntry.keyVec.first,
                    let firstHasher = nMapEntry.hashers.first else {
                    throw NSError(domain: "Missing required params", code: 0)
                }

                keyType = firstKey
                hasher = firstHasher
            case .plain:
                throw NSError(domain: "Incompatible storage type", code: 0)
            }

            let keys: [Data] = try keyParams.map { keyParam in
                let encoder = DynamicScaleEncoder(registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
                try encoder.append(keyParam, ofType: keyType)

                let encodedParam = try encoder.encode()

                return try StorageKeyFactory().createStorageKey(
                    moduleName: path.moduleName,
                    storageName: path.itemName,
                    key: encodedParam,
                    hasher: hasher
                )
            }

            let params = StorageQuery(keys: keys, blockHash: nil)

            let queryOperation = JSONRPCQueryOperation(
                engine: engine!,
                method: RPCMethod.queryStorageAt,
                parameters: params
            )

            OperationQueue().addOperations([queryOperation], waitUntilFinished: true)

            let dataList = try queryOperation.extractNoCancellableResultData().flatMap { StorageUpdateData(update: $0).changes }
                .map(\.value)

            let data = dataList.first!
            if data != nil {
                let decoder = try DynamicScaleDecoder(data: data!, registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
                return try decoder.read(type: entry.type.typeName).map(to: AccountInfo.self)
            } else {
                switch entry.modifier {
                case .defaultModifier:
                    let decoder = try DynamicScaleDecoder(data: entry.defaultValue, registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
                    return try decoder.read(type: entry.type.typeName).map(to: AccountInfo.self)
                case .optional:
                    return nil
                }
            }
        } catch {
            throw error
        }
    }

    func fetchRuntimeData() throws -> (RuntimeVersion, RuntimeMetadataProtocol, TypeRegistryCatalog) {
        do {
            // runtime version
            let versionOperation = JSONRPCListOperation<RuntimeVersion>(engine: engine!,
                                                                 method: RPCMethod.getRuntimeVersion,
                                                                 parameters: [])

            OperationQueue().addOperations([versionOperation], waitUntilFinished: true)

            let runtimeVersion = try versionOperation.extractNoCancellableResultData()

            // runtime metadata
            let metadataOperation = JSONRPCOperation<[String], String>(
                engine: engine!,
                method: RPCMethod.getRuntimeMetadata
            )

            OperationQueue().addOperations([metadataOperation], waitUntilFinished: true)

            let hexMetadata = try metadataOperation.extractNoCancellableResultData()
            let rawMetadata = try Data(hexString: hexMetadata)
            let decoder = try ScaleDecoder(data: rawMetadata)
            let runtimeMetadataContainer = try RuntimeMetadataContainer(scaleDecoder: decoder)
            let runtimeMetadata: RuntimeMetadataProtocol

            // catalog
            let commonTypesUrl = Bundle.main.url(forResource: "runtime-default", withExtension: "json")!
            let commonTypes = try Data(contentsOf: commonTypesUrl)

            let chainTypeUrl = Bundle.main.url(forResource: "runtime-peaq", withExtension: "json")!
            let chainTypes = try Data(contentsOf: chainTypeUrl)

            let catalog: TypeRegistryCatalog

            switch runtimeMetadataContainer.runtimeMetadata {
            case let .v13(metadata):
                catalog = try TypeRegistryCatalog.createFromTypeDefinition(
                    commonTypes,
                    versioningData: chainTypes,
                    runtimeMetadata: metadata
                )
                runtimeMetadata = metadata
            case let .v14(metadata):
                catalog = try TypeRegistryCatalog.createFromSiDefinition(
                    versioningData: chainTypes,
                    runtimeMetadata: metadata,
                    customTypeMapper: SiDataTypeMapper(),
                    customNameMapper: ScaleInfoCamelCaseMapper()
                )
                runtimeMetadata = metadata
            }

            return (runtimeVersion, runtimeMetadata, catalog)
        } catch {
            throw error
        }
    }

    func postData(with url: String, parameters: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONSerialization.data(withJSONObject: parameters, options: [])
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "HTTP error", code: 0, userInfo: nil)
        }

        guard let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "Invalid JSON", code: 0, userInfo: nil)
        }

        if ((200...299) + [400, 401]).contains(httpResponse.statusCode) {
            return result
        } else {
            throw NSError(domain: "HTTP error", code: httpResponse.statusCode, userInfo: nil)
        }
    }

    func getData(with url: String) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "HTTP error", code: 0, userInfo: nil)
        }

        guard let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "Invalid JSON", code: 0, userInfo: nil)
        }

        if ((200...299) + [400, 401]).contains(httpResponse.statusCode) {
            return result
        } else {
            throw NSError(domain: "HTTP error", code: httpResponse.statusCode, userInfo: nil)
        }
    }
}
