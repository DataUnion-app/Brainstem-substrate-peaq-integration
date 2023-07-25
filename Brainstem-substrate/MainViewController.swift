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
    @IBOutlet weak var publicKeyLabel: UILabel!
    @IBOutlet weak var accountAddressLabel: UILabel!
    @IBOutlet weak var nonceLabel: UILabel!
    @IBOutlet weak var accessTokenLabel: UILabel!
    @IBOutlet weak var refreshTokenLabel: UILabel!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var errorLabel: UILabel!

    let brainstem_base_url = "https://crab.dev.dataunion.app"
    let dev_base_url = "https://crab.dev.dataunion.app"
    let test_address_1 = "5FR9vPs6uYUCbh6ft82jTq18coqsr1EyK1yZKLKACJfYLw3r"
    let test_address_2 = "5CX6AYwdixAFUQW9NSNZvk4umWpEVPwuhaPSS4Tn5S1GXT49"
    var test_mnemonic_1 = "strong need allow car sunny visual dog grab slam adjust pave illegal"
    let peaq_url = "wss://wss.agung.peaq.network"
    let peaq_testnet_url = "wss://wsspc1-qa.agung.peaq.network"

    var engine: WebSocketEngine? = nil
    var runtimeVersion: RuntimeVersion?
    var runtimeMetadata: RuntimeMetadataProtocol?
    var catalog: TypeRegistryCatalog?
    var assetModelPeaqLive: AssetModel?
    var assetModelPeaqTest: AssetModel?
    let liveOrTest = false
    var test_address = ""
    var test_mnemonic = ""
    var register_url = "/register"
    var get_nonce_url = "/get-nonce?public_address=$[public_address]"
    var login_url = "/login"

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        test_address = test_address_2
        test_mnemonic = test_mnemonic_1
        register_url = brainstem_base_url + register_url
        get_nonce_url = brainstem_base_url + get_nonce_url
        login_url = brainstem_base_url + login_url

        engine = WebSocketEngine(urls: [URL(string: liveOrTest ? peaq_url : peaq_testnet_url)!], logger: nil)
        assetModelPeaqLive = AssetModel(assetId: 0, icon: nil, name: nil, symbol: "AGNG", precision: 18, priceId: nil, staking: nil, type: nil, typeExtras: nil, buyProviders: nil)
        assetModelPeaqTest = AssetModel(assetId: 1, icon: nil, name: nil, symbol: "PEAQ", precision: 18, priceId: nil, staking: nil, type: nil, typeExtras: nil, buyProviders: nil)

        do {
            (runtimeVersion, runtimeMetadata, catalog) = try fetchRuntimeData()
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
    
    @IBAction func actionCreateWallet(_ sender: Any) {
        createWallet()
    }

    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
        connectPeaqNetwork()
    }

    func fetchRuntimeData() throws -> (RuntimeVersion, RuntimeMetadataProtocol, TypeRegistryCatalog) {
        do {
            // runtime version
            let versionOperation = JSONRPCListOperation<RuntimeVersion>(engine: engine!,
                                                                 method: RPCMethod.getRuntimeVersion,
                                                                 parameters: [])

            OperationQueue().addOperations([versionOperation], waitUntilFinished: true)

            let runtimeVersion = try versionOperation.extractNoCancellableResultData()
            
            // runtime metadata
            let metadataOperation = JSONRPCOperation<[String], String>(
                engine: engine!,
                method: RPCMethod.getRuntimeMetadata
            )
            
            OperationQueue().addOperations([metadataOperation], waitUntilFinished: true)
            
            let hexMetadata = try metadataOperation.extractNoCancellableResultData()
            let rawMetadata = try Data(hexString: hexMetadata)
            let decoder = try ScaleDecoder(data: rawMetadata)
            let runtimeMetadataContainer = try RuntimeMetadataContainer(scaleDecoder: decoder)
            let runtimeMetadata: RuntimeMetadataProtocol
            
            // catalog
            let commonTypesUrl = Bundle.main.url(forResource: "runtime-default", withExtension: "json")!
            let commonTypes = try Data(contentsOf: commonTypesUrl)

            let chainTypeUrl = Bundle.main.url(forResource: "runtime-peaq", withExtension: "json")!
            let chainTypes = try Data(contentsOf: chainTypeUrl)

            let catalog: TypeRegistryCatalog
            
            switch runtimeMetadataContainer.runtimeMetadata {
            case let .v13(metadata):
                catalog = try TypeRegistryCatalog.createFromTypeDefinition(
                    commonTypes,
                    versioningData: chainTypes,
                    runtimeMetadata: metadata
                )
                runtimeMetadata = metadata
            case let .v14(metadata):
                catalog = try TypeRegistryCatalog.createFromSiDefinition(
                    versioningData: chainTypes,
                    runtimeMetadata: metadata,
                    customTypeMapper: SiDataTypeMapper(),
                    customNameMapper: ScaleInfoCamelCaseMapper()
                )
                runtimeMetadata = metadata
            }
            
            return (runtimeVersion, runtimeMetadata, catalog)
        } catch {
            throw error
        }
    }
}
