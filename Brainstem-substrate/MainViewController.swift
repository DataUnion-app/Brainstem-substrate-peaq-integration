//
//  MainViewController.swift
//  Brainstem-substrate
//
//  Created by macos on 7/6/23.
//

import UIKit
import IrohaCrypto
import RobinHood
import SubstrateSdk

struct RuntimeVersion: Codable, Equatable {
    let specVersion: UInt32
    let transactionVersion: UInt32
}

class MainViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    @IBAction func actionCreateWallet(_ sender: Any) {
        do {
            let mnemonicCreator: IRMnemonicCreatorProtocol = IRMnemonicCreator()
            let mnemonic = try mnemonicCreator.randomMnemonic(.entropy128)

            guard let mnemonicString = try? IRMnemonicCreator()
                    .mnemonic(fromList: mnemonic.allWords().joined(separator: " "))
            else {
                return
            }
            print(mnemonic.allWords().joined(separator: " "))
            
            let seedResult = try SeedFactory().deriveSeed(from: mnemonicString.toString(), password: "")
            print(seedResult.seed.miniSeed.toHex())
            
//            switch cryptoType {
//            case .sr25519:
//                return SR25519KeypairFactory()
//            case .ed25519:
//                return Ed25519KeypairFactory()
//            case .substrateEcdsa:
//                return EcdsaKeypairFactory()
//            case .ethereumEcdsa:
//                return BIP32KeypairFactory()
//            }
            let keypairFactory = SR25519KeypairFactory() //Polkadot Keypair Factory
            let chaincodes: [Chaincode] = []
            
            let keypair = try keypairFactory.createKeypairFromSeed(
                seedResult.seed.miniSeed,
                chaincodeList: chaincodes
            )
            
            let publicKey = keypair.publicKey().rawData()
            let secretKey = keypair.privateKey().rawData()
            print(publicKey.toHex())
            print(secretKey.toHex())
            
            let accountId = try publicKey.publicKeyToAccountId()
            print(accountId.toHex())
            let accountAddress = try SS58AddressFactory().address(fromAccountId: accountId, type: 0) //Polkadot Account Address
            print(accountAddress)
            
//            let metaId = UUID().uuidString
//            print(metaId)

        } catch {
            print(error)
        }
    }
    
    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
        do {
            // peaq connect, runtime version
            let operationQueue = OperationQueue()
            let peaq_url = "wss://wsspc1-qa.agung.peaq.network"
            let url = URL(string: peaq_url)!
            let engine = WebSocketEngine(urls:[url])!
            
            let operation = JSONRPCListOperation<RuntimeVersion>(engine: engine,
                                                                 method: "chain_getRuntimeVersion",
                                                                 parameters: [])
            operationQueue.addOperations([operation], waitUntilFinished: true)

            let result = try operation.extractResultData(throwing: BaseOperationError.parentOperationCancelled)
            print(result)
            
            // peaq connect, health check
            let operationHealthCheck = JSONRPCListOperation<SubstrateHealthResult>(engine: engine,
                                                                               method: RPCMethod.healthCheck,
                                                                               parameters: [])
            operationQueue.addOperations([operationHealthCheck], waitUntilFinished: true)

            let resultHealthCheck = try operationHealthCheck.extractResultData(throwing: BaseOperationError.parentOperationCancelled)
            print(resultHealthCheck)

        } catch {
            print(error)
        }
    }
}
