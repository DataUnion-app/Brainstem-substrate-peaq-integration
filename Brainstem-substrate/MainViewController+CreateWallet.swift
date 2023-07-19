import SubstrateSdk
import IrohaCrypto

extension MainViewController {
    func createWallet() {
        do {
            // create polkadot wallet
            var mnemonicWords = test_mnemonic //already exist
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
            let accountAddress: String = try SS58AddressFactory().address(fromAccountId: accountId, type: UInt16(SNAddressType.genericSubstrate.rawValue))

            loginFunc(with: accountAddress, publicKeyData: publicKey, privateKeyData: secretKey)
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
                    publicKeyLabel.text = "Public Key: " + publicKeyData.toHex()
                    accountAddressLabel.text = "Account Address: " + accountAddress
                    nonceLabel.text = "Nonce: " + nonce

                    if let access_token = result["access_token"] as? String {
                        accessTokenLabel.text = "Access token: " + access_token
                    }
                    if let refresh_token = result["refresh_token"] as? String {
                        refreshTokenLabel.text = "Refresh token: " + refresh_token
                    }
                }
            } catch {
                errorLabel.text = error.localizedDescription
            }
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
