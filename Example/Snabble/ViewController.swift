//
//  ViewController.swift
//  Snabble
//
//  Copyright (c) 2018 snabble GmbH. All rights reserved.
//

import UIKit
import Snabble

class ViewController: UIViewController {

    @IBOutlet weak var buttonContainer: UIStackView!
    @IBOutlet weak var spinner: UIActivityIndicatorView!

    private var shoppingCart = ShoppingCart(CartConfig())

    override func viewDidLoad() {
        super.viewDidLoad()
        self.snabbleSetup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    @IBAction func scannerButtonTapped(_ sender: Any) {
        let project = SnabbleAPI.projects[0]
        let shop = project.shops[0]
        let scanner = ScannerViewController(self.shoppingCart, shop, delegate: self)
        scanner.navigationItem.leftBarButtonItem = nil
        self.navigationController?.pushViewController(scanner, animated: true)
    }

    @IBAction func shoppingCartButtonTapped(_ sender: Any) {
        let shoppingCart = ShoppingCartViewController(self.shoppingCart, delegate: self)
        self.navigationController?.pushViewController(shoppingCart, animated: true)
    }

    func snabbleSetup() {
        let APPID = "your-app-id-here"
        let APPSECRET = "your-app-secret-here"
        let apiConfig = SnabbleAPIConfig(appId: APPID, baseUrl: "https://api.snabble-testing.io", secret: APPSECRET)

        SnabbleAPI.setup(apiConfig) {
            // initial config parsed/loaded
            let project = SnabbleAPI.projects[0]

            // register the project with the UI components
            SnabbleUI.register(project)

            // initialize the product database for this project
            let productProvider = SnabbleAPI.productProvider(for: project)
            productProvider.setup() { _ in
                self.spinner.stopAnimating()
                self.buttonContainer.isHidden = false

                var cartConfig = CartConfig()
                cartConfig.project = project
                cartConfig.shop = project.shops[0]
                self.shoppingCart = ShoppingCart(cartConfig)
            }
        }
    }
}

extension ViewController: ScannerDelegate {
    // called when the scanner needs to close itself
    func closeScanningView() {
        self.navigationController?.popViewController(animated: true)
    }
}

extension ViewController: ShoppingCartDelegate {
    func gotoPayment(_ info: SignedCheckoutInfo, _ cart: ShoppingCart) {
        let process = PaymentProcess(info, cart, delegate: self)

        process.start { viewController, error in
            if let vc = viewController {
                self.navigationController?.pushViewController(vc, animated: true)
            } else {
                self.showWarningMessage("Error creating payment process: \(error!))")
            }
        }
    }

    func gotoScanner() {
        // implement this method to switch from the shopping cart's empty state to the scanner
    }

    func handleCheckoutError(_ error: ApiError?) -> Bool {
        if let error = error {
            NSLog("checkout error: \(error)")
        }
        return false
    }
}

/// implement this method to track an event generated from the SDK in your analytics system
extension ViewController: AnalyticsDelegate {
    func track(_ event: AnalyticsEvent) {
        NSLog("track: \(event)")
    }
}

/// implement these methods to show warning/info messages on-screen, e.g. as toasts
extension ViewController: MessageDelegate {
    func showInfoMessage(_ message: String) {
        NSLog("warning: \(message)")
    }

    func showWarningMessage(_ message: String) {
        NSLog("info: \(message)")
    }
}

extension ViewController: PaymentDelegate {
    func paymentFinished(_ success: Bool, _ cart: ShoppingCart) {
        cart.removeAll()
        self.navigationController?.popViewController(animated: true)
    }

    func handlePaymentError(_ error: ApiError?) -> Bool {
        if let error = error {
            NSLog("payment error: \(error)")
        }
        return false
    }
}

