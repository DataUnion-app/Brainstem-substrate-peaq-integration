import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func connectPeaqNetwork() {
        // display account balance
        getAccountBalance()
    }

    func getAccountBalance() {
        let addressFactory = SS58AddressFactory()
        let accountId = try! addressFactory.accountId(from: test_address)

        let operationQueue = OperationQueue()

        let hasher: StorageHasher = StorageHasher.blake128Concat
        
        let keyParams = [accountId]
        
        let remoteFactory = StorageKeyFactory()
        
        do {
            let keys: [Data] = try keyParams.map { keyParam in
                let encoder = ScaleEncoder()
                
                encoder.appendRaw(data: keyParam)
                let keyParamData = encoder.encode()
                
                return try remoteFactory.createStorageKey(
                    moduleName: "System",
                    storageName: "Account",
                    key: keyParamData,
                    hasher: hasher
                )
            }
            
            let params = StorageQuery(keys: keys, blockHash: nil)

            let operation = JSONRPCQueryOperation(engine: engine!,
                                                                 method: RPCMethod.queryStorageAt,
                                                                 parameters: params)

            operationQueue.addOperations([operation], waitUntilFinished: true)

            let result = try operation.extractResultData(throwing: BaseOperationError.parentOperationCancelled).flatMap { $0 }
            
            let dataList = result
                .flatMap { StorageUpdateData(update: $0).changes }
                .map(\.value)
            
            if let data = dataList[0] {
                let decoder = try ScaleDecoder(data: data)
                
                // ["nonce", "consumers", "providers", "sufficients", "data"]
                // ["free", "reserved", "miscFrozen", "feeFrozen"]
                
                let typeArray = [["nonce": 4], ["consumers" : 4], ["providers": 4], ["sufficients": 4], ["free": 16], ["reserved": 16], ["miscFrozen": 16], ["feeFrozen": 16]]

                let resultArray = try typeArray.reduce(into: [BigUInt]()) { (result, type) in
                    if let value = type.values.first {
                        let info = try decoder.readAndConfirm(count: value)
                        result.append(BigUInt(Data(info.reversed())))
                    }
                }
                
                print("nonce, consumers, providers, sufficients:", resultArray[0], resultArray[1], resultArray[2], resultArray[3])
                print("free, reserved, miscFrozen, feeFrozen:", resultArray[4], resultArray[5], resultArray[6], resultArray[7])
                
                let balanceString = Decimal.fromSubstrateAmount(
                    resultArray[4] - max(resultArray[6], resultArray[7]), //free - max(miscFrozen, feeFrozen)
                    precision: 18
                ) ?? 0.0
                
                balanceLabel.text = "Balance: \(balanceString) AGNG"
            }
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
}
