//
//  OnlineCheckoutViewController.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import UIKit

final class OnlineCheckoutViewController: UIViewController {

    @IBOutlet weak var codeImage: UIImageView!
    @IBOutlet weak var explanationLabel: UILabel!
    @IBOutlet weak var waitLabel: UILabel!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var codeWidth: NSLayoutConstraint!
    
    private var cart: ShoppingCart
    private weak var delegate: PaymentDelegate!

    private var process: CheckoutProcess
    private var poller: PaymentProcessPoller?
    private var initialBrightness: CGFloat = 0

    init(_ process: CheckoutProcess, _ data: PaymentMethodData, _ cart: ShoppingCart, _ delegate: PaymentDelegate) {
        self.process = process
        self.cart = cart
        self.delegate = delegate
        
        super.init(nibName: nil, bundle: SnabbleBundle.main)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Snabble.Payment.confirm".localized()

        self.explanationLabel.text = "Snabble.Payment.presentCode".localized()
        self.waitLabel.text = "Snabble.Payment.waiting".localized()

        let components = process.links.`self`.href.components(separatedBy: "/")
        let id = components.last ?? "n/a"

        self.codeImage.image = QRCode.generate(for: id, scale: 5)
        self.codeWidth.constant = self.codeImage.image?.size.width ?? 0

        self.cancelButton.setTitle("Snabble.Cancel".localized(), for: .normal)

        self.navigationItem.hidesBackButton = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.cancelButton.alpha = 0
        self.cancelButton.isUserInteractionEnabled = false

        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { timer in
            UIView.animate(withDuration: 0.2) {
                self.cancelButton.alpha = 1
            }
            self.cancelButton.isUserInteractionEnabled = true
        }

        UIApplication.shared.isIdleTimerDisabled = true

        self.initialBrightness = UIScreen.main.brightness
        if self.initialBrightness < 0.5 {
            UIScreen.main.brightness = 0.5
            self.delegate.track(.brightnessIncreased)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.delegate.track(.viewOnlineCheckout)

        let poller = PaymentProcessPoller(self.process, SnabbleUI.project)

        var events = [PaymentEvent: Bool]()
        poller.waitFor([.approval, .paymentSuccess]) { event in
            events.merge(event, uniquingKeysWith: { b1, b2 in b1 })

            if let approval = events[.approval], approval == false {
                self.paymentFinished(false, poller.updatedProcess)
                return
            }

            if let approval = events[.approval], let paymentSuccess = events[.paymentSuccess] {
                self.paymentFinished(approval && paymentSuccess, poller.updatedProcess)
            }
        }
        self.poller = poller
    }

    override func viewWillDisappear(_ animated: Bool) {
        UIScreen.main.brightness = self.initialBrightness

        self.poller?.stop()
        self.poller = nil

        self.delegate.track(.paymentCancelled)

        UIApplication.shared.isIdleTimerDisabled = false
    }

    @IBAction func cancelButtonTapped(_ sender: UIButton) {
        self.poller?.stop()
        self.poller = nil

        self.delegate.track(.paymentCancelled)

        self.process.abort(SnabbleUI.project) { _ in
            if let cartVC = self.navigationController?.viewControllers.first(where: { $0 is ShoppingCartViewController}) {
                self.navigationController?.popToViewController(cartVC, animated: true)
            } else {
                self.navigationController?.popToRootViewController(animated: true)
            }
        }
    }

    private func paymentFinished(_ success: Bool, _ process: CheckoutProcess) {
        self.poller = nil
        
        if success {
            self.cart.removeAll(endSession: true)
        }
        self.delegate.paymentFinished(success, self.cart, process)
    }
}
