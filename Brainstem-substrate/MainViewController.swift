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
    var test_address = ""
    var test_mnemonic = ""
    var register_url = "/register"
    var get_nonce_url = "/get-nonce?public_address=$[public_address]"
    var login_url = "/login"

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        engine = WebSocketEngine(urls: [URL(string: peaq_url)!], logger: nil)
        test_address = test_address_2
        test_mnemonic = test_mnemonic_1
        register_url = brainstem_base_url + register_url
        get_nonce_url = brainstem_base_url + get_nonce_url
        login_url = brainstem_base_url + login_url
    }
    
    @IBAction func actionCreateWallet(_ sender: Any) {
        createWallet()
    }

    @IBAction func actionConnectPeaqNetwork(_ sender: Any) {
        connectPeaqNetwork()
    }
}
