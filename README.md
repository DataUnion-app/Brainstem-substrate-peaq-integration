## Brainstem-substrate

# Create Wallet & Login
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

# Connect Peaq network
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



