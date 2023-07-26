import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func connectPeaqNetwork() {
        // display account balance
        do {
            let accountInfo = try getAccountBalance(accountAddress: test_address)
            if (accountInfo != nil) {
                let available = accountInfo.map {
                    Decimal.fromSubstrateAmount(
                        $0.data.available,
                        precision: liveOrTest ? Int16(assetModelPeaqLive!.precision) : Int16(assetModelPeaqTest!.precision)
                    ) ?? 0.0
                } ?? 0.0

                balanceLabel.text = "Balance: \(available.stringWithPointSeparator) \(liveOrTest ? assetModelPeaqLive!.symbol : assetModelPeaqTest!.symbol)"
            } else {
                errorLabel.text = "Unexpected Error"
            }
        } catch {
            errorLabel.text = error.localizedDescription
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
                return nil
            }
        } catch {
            throw error
        }
    }
}
