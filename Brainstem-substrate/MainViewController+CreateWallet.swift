import SubstrateSdk
import IrohaCrypto

extension MainViewController {
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
}
