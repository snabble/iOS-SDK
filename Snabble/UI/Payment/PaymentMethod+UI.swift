//
//  PaymentMethod+UI.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import Foundation

/// map payment methods to icons and the UIViewControllers that implement them
extension PaymentMethod {
    var icon: String {
        switch self {
        case .qrCodePOS: return "payment-method-checkstand"
        case .encodedCodes: return "payment-method-checkstand"
        case .encodedCodesCSV: return "payment-method-checkstand"
        case .encodedCodesIKEA: return "payment-method-checkstand"
        case .deDirectDebit: return "payment-sepa"
        case .visa: return "payment-visa"
        case .mastercard: return "payment-mastercard"
        }
    }

    var dataRequired: Bool {
        switch self {
        case .deDirectDebit, .visa, .mastercard: return true
        case .qrCodePOS, .encodedCodes, .encodedCodesCSV, .encodedCodesIKEA: return false
        }
    }

    func processor(_ process: CheckoutProcess?, _ cart: ShoppingCart, _ delegate: PaymentDelegate) -> UIViewController? {
        if !self.rawMethod.offline && process == nil {
            return nil
        }
        if self.dataRequired && self.data == nil {
            return nil
        }

        let processor: UIViewController
        switch self {
        case .qrCodePOS:
            processor = QRCheckoutViewController(process!, cart, delegate)
        case .encodedCodes, .encodedCodesCSV, .encodedCodesIKEA:
            processor = EmbeddedCodesCheckoutViewController(process, self, cart, delegate)
        case .deDirectDebit, .visa, .mastercard:
            processor = SepaCheckoutViewController(process!, self.data!, cart, delegate)
        }
        processor.hidesBottomBarWhenPushed = true
        return processor
    }
}

/// Manage the payment process
public final class PaymentProcess {
    private(set) var signedCheckoutInfo: SignedCheckoutInfo
    private(set) var cart: ShoppingCart
    private var hudTimer: Timer?
    weak var delegate: PaymentDelegate!

    /// create a payment process
    ///
    /// - Parameters:
    ///   - signedCheckoutInfo: the checkout info for this process
    ///   - cart: the cart for this process
    ///   - delegate: the `PaymentDelegate` to use
    public init(_ signedCheckoutInfo: SignedCheckoutInfo, _ cart: ShoppingCart, delegate: PaymentDelegate) {
        self.signedCheckoutInfo = signedCheckoutInfo
        self.cart = cart
        self.delegate = delegate
    }

    /// start a payment process
    ///
    /// if the checkout allows multiple payment methods, offer a selection
    /// otherwise, directly create the corresponding view controller for the selected payment method
    ///
    /// - Parameters:
    ///   - completion: a closure called when the payment method has been determined.
    ///   - result: the view controller to present for this payment process or the error
    public func start(completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> () ) {
        let info = self.signedCheckoutInfo

        let paymentMethods = self.mergePaymentMethodList(info.checkoutInfo.paymentMethods)

        switch paymentMethods.count {
        case 0:
            completion(Result.failure(SnabbleError.noPaymentAvailable))
        case 1:
            let method = paymentMethods[0]
            self.start(method) { result in
                completion(result)
            }
        default:
            let paymentSelection = PaymentMethodSelectionViewController(self, paymentMethods)
            completion(Result.success(paymentSelection))
        }
    }

    func mergePaymentMethodList(_ methods: [RawPaymentMethod]) -> [PaymentMethod] {
        let userData = self.delegate.getPaymentData()
        var result = [PaymentMethod]()
        for method in methods {
            switch method {
            case .encodedCodes: result.append(.encodedCodes)
            case .encodedCodesCSV: result.append(.encodedCodesCSV)
            case .encodedCodesIKEA: result.append(.encodedCodesIKEA)
            case .qrCodePOS: result.append(.qrCodePOS)
            case .deDirectDebit:
                let sepa = userData.filter { if case .deDirectDebit = $0 { return true } else { return false } }
                if sepa.count > 0 {
                    result.append(contentsOf: sepa.reversed())
                } else {
                    result.append(.deDirectDebit(nil))
                }
            case .creditCardVisa:
                let visa = userData.filter { if case .visa = $0 { return true } else { return false } }
                if visa.count > 0 {
                    result.append(contentsOf: visa.reversed())
                } else {
                    result.append(.visa(nil))
                }
            case .creditCardMastercard:
                let mc = userData.filter { if case .mastercard = $0 { return true } else { return false } }
                if mc.count > 0 {
                    result.append(contentsOf: mc.reversed())
                } else {
                    result.append(.mastercard(nil))
                }
            }
        }

        return result.reversed()
    }

    func start(_ method: PaymentMethod, completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> () ) {
        UIApplication.shared.beginIgnoringInteractionEvents()
        self.startBlurOverlayTimer()

        self.signedCheckoutInfo.createCheckoutProcess(SnabbleUI.project, paymentMethod: method, timeout: 20) { result in
            self.hudTimer?.invalidate()
            self.hudTimer = nil
            UIApplication.shared.endIgnoringInteractionEvents()
            self.hideBlurOverlay()
            switch result {
            case .success(let process):
                if let processor = method.processor(process, self.cart, self.delegate) {
                    completion(Result.success(processor))
                } else {
                    self.delegate.showWarningMessage("Snabble.Payment.errorStarting".localized())
                }
            case .failure(let error):
                self.startFailed(method, error, completion)
            }
        }
    }

    private func startFailed(_ method: PaymentMethod, _ error: SnabbleError?, _ completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> () ) {
        var handled = false
        if let error = error {
            handled = self.delegate.handlePaymentError(method, error)
        }
        if !handled {
            if method.rawMethod.offline, let processor = method.processor(nil, self.cart, self.delegate) {
                completion(Result.success(processor))
                self.retryCreatingMissingCheckout(method)
            } else {
                self.delegate.showWarningMessage("Snabble.Payment.errorStarting".localized())
            }
        }
    }

    private func startBlurOverlayTimer() {
        self.hudTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
            self.showBlurOverlay()
        }
    }

    func track(_ event: AnalyticsEvent) {
        self.delegate.track(event)
    }

    // retry creating the checkout info / checkout process that is potentially missing
    private func retryCreatingMissingCheckout(_ method: PaymentMethod) {
        let project = SnabbleUI.project
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.cart.createCheckoutInfo(project) { result in
                if case Result.success(let info) = result {
                    info.createCheckoutProcess(project, paymentMethod: method) { _ in }
                }
            }
        }
    }

    private var blurView: UIView?

    private func showBlurOverlay() {
        let blurEffect = UIBlurEffect(style: .dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = self.delegate.view.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
        activityIndicator.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        activityIndicator.startAnimating()

        blurEffectView.contentView.addSubview(activityIndicator)
        activityIndicator.center = blurEffectView.contentView.center

        self.delegate.view.addSubview(blurEffectView)
        self.blurView = blurEffectView
    }

    private func hideBlurOverlay() {
        self.blurView?.removeFromSuperview()
        self.blurView = nil
    }

}
