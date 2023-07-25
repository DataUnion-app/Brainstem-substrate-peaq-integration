import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func connectPeaqNetwork() {
        // display account balance
        do {
            let availableBalance = try getAccountBalance()
            balanceLabel.text = "Balance: \(availableBalance)"
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }

    func getAccountBalance() throws -> String {
        do {
            let addressFactory = SS58AddressFactory()
            let accountId = try! addressFactory.accountId(from: test_address)
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
                parameters: params,
                timeout: 60
            )

            OperationQueue().addOperations([queryOperation], waitUntilFinished: true)

            let result = try queryOperation.extractNoCancellableResultData().flatMap { $0 }
            
            let dataList = result
                .flatMap { StorageUpdateData(update: $0).changes }
                .map(\.value)
            
            let resultChangesData = result.flatMap { StorageUpdateData(update: $0).changes }
            
            let keyedEncodedItems = resultChangesData.reduce(into: [Data: Data]()) { result, change in
                if let data = change.value {
                    result[change.key] = data
                }
            }
            
            let allKeys = resultChangesData.map(\.key)
            
            let items: [AccountInfo?] = try dataList.map { data in
                guard let entry = runtimeMetadata!.getStorageMetadata(
                    in: path.moduleName,
                    storageName: path.itemName
                ) else {
                    throw NSError(domain: "Invalid storage path", code: 0)
                }

                if let data = data {
                    let decoder = try DynamicScaleDecoder(data: data, registry: catalog!, version: UInt64(runtimeVersion!.specVersion))
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
            }
            
            let keyedItems = zip(allKeys, items).reduce(into: [Data: AccountInfo]()) { result, item in
                result[item.0] = item.1
            }
            
            let originalIndexedKeys = keys.enumerated().reduce(into: [Data: Int]()) { result, item in
                result[item.element] = item.offset
            }
            
            let responseAll = allKeys.map { key in
                StorageResponse(key: key, data: keyedEncodedItems[key], value: keyedItems[key])
            }.sorted { response1, response2 in
                guard
                    let index1 = originalIndexedKeys[response1.key],
                    let index2 = originalIndexedKeys[response2.key] else {
                    return false
                }

                return index1 < index2
            }
            
            guard let response = responseAll.first else {
                throw BaseOperationError.unexpectedDependentResult
            }

            let accountInfo = response.value
            let available = accountInfo.map {
                Decimal.fromSubstrateAmount(
                    $0.data.available,
                    precision: liveOrTest ? Int16(assetModelPeaqLive!.precision) : Int16(assetModelPeaqTest!.precision)
                ) ?? 0.0
            } ?? 0.0

            return available.stringWithPointSeparator + " \(liveOrTest ? assetModelPeaqLive!.symbol : assetModelPeaqTest!.symbol)"
        } catch {
            throw error
        }
    }
}
