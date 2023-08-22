# Brainstem substrate wallet integration

This work was done by DataUnion (https://dataunion.app) on behalf of Brainstem (https://brainstem.health) for a grant from peaq (https://peaq.network).
The code is an implementation of a substrate wallet in Swift. This wallet is then used to register/login to the Brainstem DataUnion backend. A sample health data file is uploaded from a sensor, that sensor is registered with the peaq network and receives a DID as its identifier. This identifier is attached to the sensor data in the Brainstem DataUnion.

## How to run the code
    - Install XCode(> 13.4.1) on Mac
    - Open the terminal and go to the project directory, run the 'pod install'
    - Open the Brainstem-substrate.xcworkspace file in XCode and run in Simulator
    - There is 4 buttons, 'Create Wallet and Login', 'Connect Peaq Network', 'Generate PeadDid', 'Read PeaqDid'
    - Tap 'Create Wallet and Login', wait some time, it will show the result or error
    - Tap 'Connect Peaq Network', wait some time, it will show wallet balance in peaq network or error
    - Input PeaqDid name and value, and tap 'Generate PeadDid', wait some time, it will show the hash key for generated PeaqDid or error
    - Input PeaqDid name to read, and tap 'Read PeaqDid', wait some time, it will show the result or error
    
## How to replicate the code
    - Create wallet and Login
        In MainViewController.swift
        @IBAction func actionCreateWallet(_ sender: Any) {
            do {
                engine = WebSocketEngine(urls: [URL(string: liveOrTest ? peaq_url : peaq_testnet_url)!], logger: nil)
                (runtimeVersion, runtimeMetadata, catalog) = try fetchRuntimeData()
                createWallet(mnemonic: test_mnemonic_1)
            } catch {
                errorLabel.text = error.localizedDescription
            }
        }
        
        In MainViewController+CreateWallet.swift
        func createWallet(mnemonic: String) {
            do {
                // create polkadot wallet
                var mnemonicWords = mnemonic // already exist
                if (mnemonicWords == "") { // or create new
                    let mnemonicCreator: IRMnemonicCreatorProtocol = IRMnemonicCreator()
                    let mnemonic = try mnemonicCreator.randomMnemonic(.entropy128)
                    mnemonicWords = mnemonic.allWords().joined(separator: " ")
                }

                let seedResult = try SeedFactory().deriveSeed(from: mnemonicWords, password: "")

                let keypairFactory = SR25519KeypairFactory()
                let keypair = try keypairFactory.createKeypairFromSeed(
                    seedResult.seed.miniSeed,
                    chaincodeList: []
                )

                let publicKey = keypair.publicKey().rawData()
                let secretKey = keypair.privateKey().rawData()

                let accountId = try publicKey.publicKeyToAccountId()
                self.test_address_1 = try SS58AddressFactory().address(fromAccountId: accountId, type: UInt16(SNAddressType.genericSubstrate.rawValue))

                loginFunc(with: self.test_address_1!, publicKeyData: publicKey, privateKeyData: secretKey)
            } catch {
                errorLabel.text = error.localizedDescription
            }
        }
        
        func loginFunc(with accountAddress: String, publicKeyData: Data, privateKeyData: Data) {
            Task {
                do {
                    // register wallet
                    var parameters: [String: Any] = [
                        "public_address": accountAddress,
                        "source": "brainstem",
                        "referral_id": "",
                        "wallet": "peaq",
                    ]

                    var result = try await postData(with: register_url, parameters: parameters)
                    var nonce: String = ""
                    if let status = result["status"] as? String, status == "success" {
                        if let nonceResult = result["nonce"] as? Int {
                            nonce = String(nonceResult)
                        }
                    } else {
                        let url = get_nonce_url.replacingOccurrences(of: "$[public_address]", with: accountAddress)
                        result = try await getData(with: url)
                        if let nonceResult = result["nonce"] as? Int {
                            nonce = String(nonceResult)
                        }
                    }

                    // sign nonce
                    if (nonce == "") {
                        return
                    }

                    let originalData = nonce.data(using: .utf8)!
                    print(originalData.toHex())
                    let privateKey = try SNPrivateKey(rawData: privateKeyData)
                    let publicKey = try SNPublicKey(rawData: publicKeyData)

                    let signer = SNSigner(keypair: SNKeypair(privateKey: privateKey, publicKey: publicKey))
                    let signature = try signer.sign(originalData)
                    print(signature)
                    print(signature.rawData().toHex())

                    // login
                    parameters = [
                        "public_address": accountAddress,
                        "source": "brainstem",
                        "signature": signature.rawData().toHex(),
                    ]
                    result = try await postData(with: login_url, parameters: parameters)

                    if let status = result["status"] as? String, status == "success" {
                        var resultString = "Public Key: " + publicKeyData.toHex()
                        resultString += "\nAccount Address: " + accountAddress
                        resultString += "\nNonce: " + nonce

                        if let access_token = result["access_token"] as? String {
                            self.accessToken = access_token
                            resultString += "\nAccess token: " + access_token
                            print("access_token", access_token)
                        }
                        if let refresh_token = result["refresh_token"] as? String {
                            self.refreshToken = refresh_token
                            resultString += "\nRefresh token: " + refresh_token
                            print("refresh_token", refresh_token)
                        }
                        resultLabel.text = resultString
                    }
                } catch {
                    errorLabel.text = error.localizedDescription
                }
            }
        }
        
    - Connect Peaq Network
    In MainViewController.swift
    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
        if (self.refreshToken == nil) {
            return
        }

        connectPeaqNetwork(accountAddress: test_address_1!)
    }
    
    In MainViewController+ConnectPeaqNetwork.swift
    func connectPeaqNetwork(accountAddress: String) {
        // display account balance
        do {
            self.accountInfo = try getAccountBalance(accountAddress: accountAddress)
            if (self.accountInfo != nil) {
                let available = self.accountInfo.map {
                    Decimal.fromSubstrateAmount(
                        $0.data.available,
                        precision: liveOrTest ? Int16(assetModelPeaqLive!.precision) : Int16(assetModelPeaqTest!.precision)
                    ) ?? 0.0
                } ?? 0.0

                resultLabel.text = "Balance: \(available.stringWithPointSeparator) \(liveOrTest ? assetModelPeaqLive!.symbol : assetModelPeaqTest!.symbol)"
            } else {
                errorLabel.text = "Unexpected Error"
            }
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
    
    - Generate PeaqDid
    In MainViewController.swift
    @IBAction func actionGenerateDid(_ sender: Any) {
        // owner account must have some balance.
        if (self.accountInfo == nil) {
            return
        }

        resultLabel.text = "Result"
        errorLabel.text = "Error"

        if didNameEdit.text == nil || didNameEdit.text!.isEmpty {
            let alertController = UIAlertController(title: "Please input PeaqDID name", message: "", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            present(alertController, animated: true, completion: nil)
            return
        }

        do {
            try generatePeaqDid(ownerAccountMnemonic: test_mnemonic_1, didAccountAddress: test_address_1!, didName: didNameEdit.text!, didValue: didValueEdit.text!)
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
    
    In MainViewController+PeaqDid.swift
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
    
    - Read PeaqDid
    In MainViewController.swift
    @IBAction func actionReadDid(_ sender: Any) {
        if (self.extrinsicHash == nil) {
            return
        }

        resultLabel.text = "Result"
        errorLabel.text = "Error"

        if didNameEdit.text == nil || didNameEdit.text!.isEmpty {
            let alertController = UIAlertController(title: "Please input PeaqDID name", message: "", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            present(alertController, animated: true, completion: nil)
            return
        }

        do {
            let didInfo = try readPeaqDid(didAccountAddress: test_address_1!, didName: didNameEdit.text!)
            if (didInfo != nil) {
                resultLabel.text = "Name: \(String(data: didInfo!.name, encoding: .utf8)!), Value: \(String(data: didInfo!.value, encoding: .utf8)!), Validity: \(didInfo!.validity), Created: \(didInfo!.created)"
            } else {
                errorLabel.text = "Can't find PeaqDid for \(didNameEdit.text!)"
            }
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
    
    In MainViewController+PeaqDid.swift
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
    
    
## Create Wallet & Login
	- Generate mnemonic words with IrohaCrypto lib
	IRMnemonicCreator().randomMnemonic(.entropy128)

	- Generate keypair(publickey, privatekey) with Substrate SDK
	SR25519KeypairFactory().createKeypairFromSeed(...)

	- Generate account address with IrohaCrypto lib
    SS58AddressFactory().address(fromAccountId: accountId, type: UInt16(SNAddressType.genericSubstrate.rawValue))

    - Register wallet to backend
    register wallet with public_address, source, referral_id, wallet to backend

    - Fetch nonce from backend

    - Sign nonce with SNSigner of IrohaCrypto lib

    - login wallet to backend
    login wallet with public_address, source, signature

## Connect Peaq network
	- Establish WebSocket with peaq url
	WebSocketEngine(urls: [URL(string: peaq_url)!], logger: nil)

	- Fetch balance of wallet on peaq network
	Convert api.query.system.account(ADDR) of Polkadot.js library to swift code with Substrate Swift SDK
		1. Create Storage Key with module name ("System"), storage name ("Account")
		2. Fetch storage data from peaq network websocket with rpc method("state_queryStorageAt")
		3. Decode the result with below format
		{
			"nonce": 4 bytes,
			"consumers": 4 bytes,
			"providers": 4 bytes,
			"sufficients": 4 bytes,
			"data": {
				"free": 16 bytes,
				"reserved": 16 bytes,
				"miscFrozen": 16 bytes,
				"feeFrozen": 16 bytes,
			}
		}

		available balance is free - max(miscFrozen, feeFrozen)



&copy; DataUnion Foundation PTE. LTD. 2023
