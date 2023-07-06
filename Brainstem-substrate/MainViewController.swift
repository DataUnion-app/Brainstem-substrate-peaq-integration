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

        } catch {
            print(error)
        }
    }
    
    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
