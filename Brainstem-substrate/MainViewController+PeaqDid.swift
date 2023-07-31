import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func generatePeaqDid(ownerAccountMnemonic: String, didAccountAddress: String, didName: String, didValue: String) throws {
        do {
            let seedOwner = try SeedFactory().deriveSeed(from: ownerAccountMnemonic, password: "")
            let keypairOwner = try SR25519KeypairFactory().createKeypairFromSeed(
                seedOwner.seed.miniSeed,
                chaincodeList: []
            )

            let publicKeyOwner = keypairOwner.publicKey().rawData()
            let privateKeyOwner = keypairOwner.privateKey().rawData()

            let accountIdOwner = try publicKeyOwner.publicKeyToAccountId()
            let accountAddressOwner = try SS58AddressFactory().address(fromAccountId: accountIdOwner, type: UInt16(SNAddressType.genericSubstrate.rawValue))

            let snPrivateKey = try SNPrivateKey(rawData: privateKeyOwner)
            let snPublicKey = try SNPublicKey(rawData: publicKeyOwner)
            let signerOwner = SNSigner(keypair: SNKeypair(privateKey: snPrivateKey, publicKey: snPublicKey))

            let genesisHash = try fetchBlockHash(with: 0)

            let nonceOwner = try fetchAccountNonce(with: accountAddressOwner)

            let (eraBlockNumber, extrinsicEra) = try executeMortalEraOperation()

            let eraBlockHash = try fetchBlockHash(with: eraBlockNumber)

            var builder: ExtrinsicBuilderProtocol =
            try ExtrinsicBuilder(
                    specVersion: runtimeVersion!.specVersion,
                    transactionVersion: runtimeVersion!.transactionVersion,
                    genesisHash: genesisHash
                )
                .with(era: extrinsicEra, blockHash: eraBlockHash)
                .with(nonce: nonceOwner)
                .with(address: MultiAddress.accoundId(accountIdOwner))

            let call = try generateRuntimeCall(didAccountAddress: didAccountAddress, didName: didName, didValue: didValue)
            builder = try builder.adding(call: call)

            let signingClosure: (Data) throws -> Data = { data in
                let signedData = try signerOwner.sign(data).rawData()
                return signedData
            }

            builder = try builder.signing(
                by: signingClosure,
                of: .sr25519,
                using: DynamicScaleEncoder(registry: catalog!, version: UInt64(runtimeVersion!.specVersion)),
                metadata: runtimeMetadata!
            )

            let extrinsic = try builder.build(
                encodingBy: DynamicScaleEncoder(registry: catalog!, version: UInt64(runtimeVersion!.specVersion)),
                metadata: runtimeMetadata!
            )

//            let submitOperation = JSONRPCListOperation<String>(
//                engine: engine!,
//                method: RPCMethod.submitExtrinsic,
//                parameters: [extrinsic.toHex(includePrefix: true)]
//            )
//            OperationQueue().addOperations([submitOperation], waitUntilFinished: true)
//            return try submitOperation.extractNoCancellableResultData()

            let updateClosure: (ExtrinsicSubscriptionUpdate) -> Void = { update in
                let status = update.params.result

                DispatchQueue.main.async {
                    if case let .inBlock(extrinsicHash) = status {
                        self.engine!.cancelForIdentifier(self.extrinsicSubscriptionId!)
                        self.extrinsicSubscriptionId = nil
                        self.didCompleteExtrinsicSubmission(for: .success(extrinsicHash))
                    }
                }
            }

            let failureClosure: (Error, Bool) -> Void = { error, _ in
                DispatchQueue.main.async {
                    self.engine!.cancelForIdentifier(self.extrinsicSubscriptionId!)
                    self.extrinsicSubscriptionId = nil
                    self.didCompleteExtrinsicSubmission(for: .failure(error))
                }
            }

            self.extrinsicSubscriptionId = try engine!.subscribe(
                RPCMethod.submitAndWatchExtrinsic,
                params: [extrinsic.toHex(includePrefix: true)],
                updateClosure: updateClosure,
                failureClosure: failureClosure
            )
        } catch {
            throw error
        }
    }
    
    func readPeaqDid(didAccountAddress: String, didName: String) throws -> DidInfo? {
        do {
            let didAccountId = try SS58AddressFactory().accountId(from: didAccountAddress)
            
            let didNameData = didName.data(using: .utf8)!
            
            let keyParam = didAccountId.toHex() + didNameData.toHex()
            let keyParamData = try Data(hexString: keyParam)
            let keyParams = [keyParamData]

            let path = StorageCodingPath.attributeStore
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

                let hasedParam: Data = try StorageHasher.blake256.hash(data: encodedParam)

                return try StorageKeyFactory().createStorageKey(
                    moduleName: path.moduleName,
                    storageName: path.itemName,
                    key: hasedParam,
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
                return try decoder.read(type: entry.type.typeName).map(to: DidInfo.self)
            } else {
                return nil
            }
        } catch {
            throw error
        }
    }
}
