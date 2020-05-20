//
//  PaymentMethod+UI.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

import Foundation

/// map payment methods to icons and the UIViewControllers that implement them
extension PaymentMethod {

    var dataRequired: Bool {
        switch self {
        case .deDirectDebit, .visa, .mastercard, .americanExpress,
             .externalBilling, .paydirektOneKlick:
            return true
        case .qrCodePOS, .qrCodeOffline, .gatekeeperTerminal, .customerCardPOS:
            return false
        }
    }

    public func canStart() -> Bool {
        if !self.dataRequired {
            return true
        } else {
            return self.data != nil
        }
    }

    func processor(_ process: CheckoutProcess?, _ rawJson: [String: Any]?, _ cart: ShoppingCart, _ delegate: PaymentDelegate) -> UIViewController? {
        if !self.rawMethod.offline && process == nil {
            return nil
        }
        guard self.canStart() else {
            return nil
        }

        let processor: UIViewController
        switch self {
        case .qrCodePOS:
            processor = QRCheckoutViewController(process!, rawJson, cart, delegate)
        case .qrCodeOffline:
            if let codeConfig = SnabbleUI.project.qrCodeConfig {
                processor = EmbeddedCodesCheckoutViewController(process, rawJson, cart, delegate, codeConfig)
            } else {
                return nil
            }
        case .deDirectDebit, .visa, .mastercard, .americanExpress, .externalBilling, .paydirektOneKlick:
            processor = OnlineCheckoutViewController(process!, rawJson, cart, delegate)
        case .gatekeeperTerminal:
            processor = TerminalCheckoutViewController(process!, rawJson, cart, delegate)
        case .customerCardPOS:
            processor = CustomerCardCheckoutViewController(process!, rawJson, cart, delegate)
        }
        processor.hidesBottomBarWhenPushed = true
        return processor
    }

    public var displayName: String? {
        if let dataName = self.data?.displayName {
            return dataName
        }

        return self.rawMethod.displayName
    }
}

/// Manage the payment process
public final class PaymentProcess {
    let signedCheckoutInfo: SignedCheckoutInfo
    let cart: ShoppingCart
    private var hudTimer: Timer?
    private(set) weak var delegate: PaymentDelegate!

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

    func mergePaymentMethodList(_ methods: [PaymentMethodDescription]) -> [PaymentMethod] {
        let userData = self.getPaymentUserData(methods)
        var result = [PaymentMethod]()
        for method in methods {
            switch method.method {
            case .qrCodePOS: result.append(.qrCodePOS)
            case .qrCodeOffline: result.append(.qrCodeOffline)
            case .gatekeeperTerminal: result.append(.gatekeeperTerminal)
            case .customerCardPOS: result.append(.customerCardPOS)
            case .deDirectDebit:
                let sepa = userData.filter { if case .deDirectDebit = $0 { return true } else { return false } }
                if !sepa.isEmpty {
                    result.append(contentsOf: sepa.reversed())
                } else {
                    result.append(.deDirectDebit(nil))
                }
            case .creditCardVisa:
                let visa = userData.filter { if case .visa = $0 { return true } else { return false } }
                if !visa.isEmpty {
                    result.append(contentsOf: visa.reversed())
                } else {
                    result.append(.visa(nil))
                }
            case .creditCardMastercard:
                let mc = userData.filter { if case .mastercard = $0 { return true } else { return false } }
                if !mc.isEmpty {
                    result.append(contentsOf: mc.reversed())
                } else {
                    result.append(.mastercard(nil))
                }
            case .creditCardAmericanExpress:
                let amex = userData.filter { if case .americanExpress = $0 { return true } else { return false } }
                if !amex.isEmpty {
                    result.append(contentsOf: amex.reversed())
                } else {
                    result.append(.americanExpress(nil))
                }
            case .externalBilling:
                let billing = userData.filter { if case .externalBilling = $0 { return true } else { return false } }
                if !billing.isEmpty {
                    result.append(contentsOf: billing.reversed())
                }
            case .paydirektOneKlick:
                let paydirekt = userData.filter { if case .paydirektOneKlick = $0 { return true } else { return false } }
                if !paydirekt.isEmpty {
                    result.append(contentsOf: paydirekt.reversed())
                }
            }
        }

        return result.reversed()
    }

    // filter payment methods: if there is at least one online payment method with data, don't show other incomplete online methods
    func filterPaymentMethods(_ methods: [PaymentMethod]) -> [PaymentMethod] {
        let onlineComplete = methods.filter { !$0.rawMethod.offline && $0.data != nil }
        if onlineComplete.isEmpty {
            return methods
        }

        // remove all incomplete online methods
        var methods = methods
        for (index, method) in methods.enumerated().reversed() {
            if !method.rawMethod.offline && method.dataRequired && method.data == nil {
                methods.remove(at: index)
            }
        }
        return methods
    }

    private func getPaymentUserData(_ methods: [PaymentMethodDescription]) -> [PaymentMethod] {
        var results = [PaymentMethod]()

        // check the registered payment methods
        let details = PaymentMethodDetails.read()
        for detail in details {
            switch detail.methodData {
            case .sepa:
                let useDirectDebit = methods.first { $0.method == .deDirectDebit } != nil
                if useDirectDebit {
                    let telecash = PaymentMethod.deDirectDebit(detail.data)
                    results.append(telecash)
                }
            case .creditcard(let creditcardData):
                let data = detail.data
                let useVisa = methods.first { $0.method == .creditCardVisa } != nil
                if useVisa && creditcardData.brand == .visa {
                    let visa = PaymentMethod.visa(data)
                    results.append(visa)
                }

                let useMastercard = methods.first { $0.method == .creditCardMastercard } != nil
                if useMastercard && creditcardData.brand == .mastercard {
                    let mc = PaymentMethod.mastercard(data)
                    results.append(mc)
                }

                let useAmex = methods.first { $0.method == .creditCardAmericanExpress } != nil
                if useAmex && creditcardData.brand == .amex {
                    let amex = PaymentMethod.americanExpress(data)
                    results.append(amex)
                }
            case .tegutEmployeeCard:
                let tegut = methods.first {
                    $0.method == .externalBilling && $0.acceptedOriginTypes?.contains(.tegutEmployeeID) == true
                }
                if tegut != nil {
                    results.append(PaymentMethod.externalBilling(detail.data))
                }
            case .paydirektAuthorization:
                let usePaydirekt = methods.first { $0.method == .paydirektOneKlick } != nil
                if usePaydirekt {
                    let paydirekt = PaymentMethod.paydirektOneKlick(detail.data)
                    results.append(paydirekt)
                }
            }
        }

        return results
    }

    public func makePaymentMethod(_ rawMethod: RawPaymentMethod, _ detail: PaymentMethodDetail?) -> PaymentMethod? {
        if let detail = detail, detail.rawMethod != rawMethod {
            Log.error("payment method mismatch: \(detail.rawMethod) != \(rawMethod)")
            assert(detail.rawMethod == rawMethod)
            return nil
        }

        switch rawMethod {
        case .qrCodePOS: return .qrCodePOS
        case .qrCodeOffline: return .qrCodeOffline
        case .gatekeeperTerminal: return .gatekeeperTerminal
        case .customerCardPOS: return .customerCardPOS
        case .deDirectDebit:
            if let data = detail?.data {
                return .deDirectDebit(data)
            }
        case .creditCardVisa:
            if let data = detail?.data {
                return .visa(data)
            }
        case .creditCardMastercard:
            if let data = detail?.data {
                return .mastercard(data)
            }
        case .creditCardAmericanExpress:
            if let data = detail?.data {
                return .americanExpress(data)
            }
        case .externalBilling:
            if let data = detail?.data {
                return .externalBilling(data)
            }
        case .paydirektOneKlick:
            if let data = detail?.data {
                return .paydirektOneKlick(data)
            }
        }

        return nil
    }

    private func startFailed(_ method: PaymentMethod, _ error: SnabbleError?, _ completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> Void ) {
        var handled = false
        if let error = error {
            handled = self.delegate.handlePaymentError(method, error)
        }
        if !handled {
            if method.rawMethod.offline, let processor = method.processor(nil, nil, self.cart, self.delegate) {
                completion(Result.success(processor))
                OfflineCarts.shared.saveCartForLater(self.cart)
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

    // MARK: - blur

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

// MARK: - start payment
extension PaymentProcess {

    public func start(_ method: PaymentMethod, completion: @escaping (RawResult<CheckoutProcess, SnabbleError>) -> Void ) {
        self.signedCheckoutInfo.createCheckoutProcess(SnabbleUI.project, paymentMethod: method, timeout: 20) { result in
            if case let Result.success(process) = result.result {
                let checker = CheckoutChecks(process)
                let stopProcess = checker.handleChecks()
                if stopProcess {
                    return
                }
            }
            completion(result)
        }
    }

    /// start a payment process with the given payment method
    ///
    /// - Parameters:
    ///   - method: the payment method to use
    ///   - detail: the details for that payment method (e.g., the encrypted IBAN for SEPA)
    ///   - completion: a closure called when the payment method has been determined.
    ///   - result: the view controller to present for this payment process or the error
    public func start(_ method: RawPaymentMethod, _ detail: PaymentMethodDetail?, completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> Void ) {

        guard
            let method = self.makePaymentMethod(method, detail),
            method.canStart()
        else {
            return completion(Result.failure(SnabbleError.noPaymentAvailable))
        }

        self.start(method, completion)
    }

    func start(_ method: PaymentMethod, _ completion: @escaping (_ result: Result<UIViewController, SnabbleError>) -> Void ) {
        UIApplication.shared.beginIgnoringInteractionEvents()
        self.startBlurOverlayTimer()

        self.signedCheckoutInfo.createCheckoutProcess(SnabbleUI.project, paymentMethod: method, timeout: 20) { result in
            self.hudTimer?.invalidate()
            self.hudTimer = nil
            UIApplication.shared.endIgnoringInteractionEvents()
            self.hideBlurOverlay()
            switch result.result {
            case .success(let process):
                let checker = CheckoutChecks(process)

                let stopProcess = checker.handleChecks()
                if stopProcess {
                    return
                }

                if let processor = method.processor(process, result.rawJson, self.cart, self.delegate) {
                    completion(Result.success(processor))
                } else {
                    self.delegate.showWarningMessage("Snabble.Payment.errorStarting".localized())
                }
            case .failure(let error):
                self.startFailed(method, error, completion)
            }
        }
    }
}

// stuff that's only used by the RN wrapper
extension PaymentProcess: ReactNativeWrapper {
    public func getPaymentMethods() -> [PaymentMethod] {
        let info = self.signedCheckoutInfo
        let mergedMethods = self.mergePaymentMethodList(info.checkoutInfo.paymentMethods)
        let paymentMethods = self.filterPaymentMethods(mergedMethods)

        return paymentMethods
    }
}
