//
//  MainViewController.swift
//  Brainstem-substrate
//
//  Created by macos on 7/6/23.
//

import UIKit
import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

class MainViewController: UIViewController {
    @IBOutlet weak var didNameEdit: UITextField!
    @IBOutlet weak var didValueEdit: UITextField!
    @IBOutlet weak var resultLabel: UILabel!
    @IBOutlet weak var errorLabel: UILabel!

    let brainstem_base_url = "https://crab.brainstem.dataunion.app"
    let dev_base_url = "https://crab.dev.dataunion.app"

    let peaq_url = "wss://wss.agung.peaq.network"
    let peaq_testnet_url = "wss://wsspc1-qa.agung.peaq.network"

    var test_mnemonic_1 = "strong need allow car sunny visual dog grab slam adjust pave illegal"
    var test_address_1: String? = nil
//    var test_mnemonic_2 = "inmate shift pact lawsuit chapter drama bracket hawk bullet alone news vacuum"
//    let test_address_2 = "5EEq3C8tBC7UBiaZJX2nXUiNyhPqyDtv8ZFC8xHp4GcEyRfW"

    var engine: WebSocketEngine? = nil
    var runtimeVersion: RuntimeVersion?
    var runtimeMetadata: RuntimeMetadataProtocol?
    var catalog: TypeRegistryCatalog?
    var assetModelPeaqLive: AssetModel?
    var assetModelPeaqTest: AssetModel?
    let liveOrTest = false
    var extrinsicSubscriptionId: UInt16?
    var extrinsicHash: String? = nil

    var register_url = "/register"
    var get_nonce_url = "/get-nonce?public_address=$[public_address]"
    var login_url = "/login"
    var refresh_url = "/refresh"
    var annotation_url = "/api/v1/metadata/annotation"

    static let fallbackMaxHashCount: BlockNumber = 250
    static let maxFinalityLag: BlockNumber = 5
    static let fallbackPeriod: Moment = 6 * 1000
    static let mortalPeriod: UInt64 = 5 * 60 * 1000

    var accessToken: String? = nil
    var refreshToken: String? = nil
    var accountInfo: AccountInfo? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        register_url = dev_base_url + register_url
        get_nonce_url = dev_base_url + get_nonce_url
        login_url = dev_base_url + login_url
        refresh_url = dev_base_url + refresh_url
        annotation_url = dev_base_url + annotation_url

        assetModelPeaqLive = AssetModel(assetId: 0, icon: nil, name: nil, symbol: "AGNG", precision: 18, priceId: nil, staking: nil, type: nil, typeExtras: nil, buyProviders: nil)
        assetModelPeaqTest = AssetModel(assetId: 1, icon: nil, name: nil, symbol: "PEAQ", precision: 18, priceId: nil, staking: nil, type: nil, typeExtras: nil, buyProviders: nil)
    }
    
    @IBAction func actionCreateWallet(_ sender: Any) {
        do {
            engine = WebSocketEngine(urls: [URL(string: liveOrTest ? peaq_url : peaq_testnet_url)!], logger: nil)
            (runtimeVersion, runtimeMetadata, catalog) = try fetchRuntimeData()
            createWallet(mnemonic: test_mnemonic_1)
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }

    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
        if (self.refreshToken == nil) {
            return
        }

        connectPeaqNetwork(accountAddress: test_address_1!)
    }

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

    func didCompleteExtrinsicSubmission(for result: Result<String, Error>) {
        switch result {
        case let .success(extrinsicHash):
            resultLabel.text = "Extrinsic Hash: " + extrinsicHash
            self.extrinsicHash = extrinsicHash
            print("Hash:", extrinsicHash)
        case let .failure(error):
            errorLabel.text = error.localizedDescription
        }
    }
}
