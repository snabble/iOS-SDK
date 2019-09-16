//
//  ScannerViewController.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import UIKit
import AVFoundation

public protocol ScannerDelegate: AnalyticsDelegate {
    func gotoShoppingCart()

    func scanMessageText(for: String) -> String?

    func showRecommendation(_ vc: UIViewController, _ project: Project, _ shop: Shop, _ product: Product, completion: @escaping (Bool) -> () )
}

public extension ScannerDelegate {
    func scanMessageText(for: String) -> String? { return nil }

    func showRecommendation(_ vc: UIViewController, _ project: Project, _ shop: Shop, _ product: Product, completion: @escaping (Bool) -> () ) {
        completion(false)
    }
}

public final class ScannerViewController: UIViewController {

    @IBOutlet private weak var spinner: UIActivityIndicatorView!

    @IBOutlet private weak var messageWrapper: UIView!
    @IBOutlet private weak var messageLabel: UILabel!
    @IBOutlet private weak var messageSeparatorHeight: NSLayoutConstraint!
    @IBOutlet private weak var messageTopDistance: NSLayoutConstraint!
    
    private var scanConfirmationView: ScanConfirmationView!
    private var scanConfirmationViewBottom: NSLayoutConstraint!
    private var tapticFeedback = UINotificationFeedbackGenerator()

    private var productProvider: ProductProvider
    private var shoppingCart: ShoppingCart
    private var shop: Shop

    private var lastScannedCode = ""
    private var confirmationVisible = false
    private var productType: ProductType?
    
    private let hiddenConfirmationOffset: CGFloat = 310
    private let visibleConfirmationOffset: CGFloat = -16

    private var keyboardObserver: KeyboardObserver!
    private weak var delegate: ScannerDelegate!
    private var timer: Timer?
    private var barcodeDetector: BarcodeDetector
    private var customAppearance: CustomAppearance?

    private var messageTimer: Timer?

    public init(_ cart: ShoppingCart, _ shop: Shop, _ detector: BarcodeDetector? = nil, delegate: ScannerDelegate) {
        let project = SnabbleUI.project

        self.shop = shop
        self.delegate = delegate

        self.shoppingCart = cart

        self.productProvider = SnabbleAPI.productProvider(for: project)

        self.barcodeDetector = detector ?? BuiltinBarcodeDetector(ScannerViewController.scannerAppearance())
        self.barcodeDetector.scanFormats = project.scanFormats

        super.init(nibName: nil, bundle: SnabbleBundle.main)

        self.barcodeDetector.delegate = self

        self.title = "Snabble.Scanner.title".localized()
        self.tabBarItem.image = UIImage.fromBundle("icon-scan-inactive")
        self.tabBarItem.selectedImage = UIImage.fromBundle("icon-scan-active")
        self.navigationItem.title = "Snabble.Scanner.scanningTitle".localized()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .black

        self.scanConfirmationView = ScanConfirmationView()
        if let custom = self.customAppearance {
            self.scanConfirmationView.setCustomAppearance(custom)
        }
        self.scanConfirmationView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scanConfirmationView)
        self.scanConfirmationView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16).isActive = true
        self.scanConfirmationView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16).isActive = true
        self.scanConfirmationView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        let bottom = self.scanConfirmationView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        bottom.isActive = true
        bottom.constant = self.hiddenConfirmationOffset
        self.scanConfirmationViewBottom = bottom
        self.scanConfirmationView.delegate = self
        self.scanConfirmationViewBottom.constant = self.hiddenConfirmationOffset

        NotificationCenter.default.addObserver(self, selector: #selector(self.cartUpdated(_:)), name: .snabbleCartUpdated, object: nil)

        self.messageSeparatorHeight.constant = 1.0 / UIScreen.main.scale

        let msgTap = UITapGestureRecognizer(target: self, action: #selector(self.messageTapped(_:)))
        self.messageWrapper.addGestureRecognizer(msgTap)
        self.messageTopDistance.constant = -150
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.updateCartButton()
        self.barcodeDetector.scannerWillAppear()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.keyboardObserver = KeyboardObserver(handler: self)

        self.delegate.track(.viewScanner)
        self.view.bringSubviewToFront(self.spinner)

        self.barcodeDetector.startScanning()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.barcodeDetector.scannerDidLayoutSubviews(self.view)

        self.view.bringSubviewToFront(self.messageWrapper)
        self.view.bringSubviewToFront(self.scanConfirmationView)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.barcodeDetector.stopScanning()
        self.displayScanConfirmationView(hidden: true)

        self.keyboardObserver = nil
    }

    var msgHidden = true


    private static func scannerAppearance() -> BarcodeDetectorAppearance {
        var appearance = BarcodeDetectorAppearance()

        appearance.torchButtonImage = UIImage.fromBundle("icon-light-inactive")?.recolored(with: .white)
        appearance.torchButtonActiveImage = UIImage.fromBundle("icon-light-active")
        appearance.enterButtonImage = UIImage.fromBundle("icon-entercode")?.recolored(with: .white)
        appearance.backgroundColor = SnabbleUI.appearance.buttonBackgroundColor
        appearance.textColor = SnabbleUI.appearance.buttonTextColor
        appearance.reticleCornerRadius = 3

        return appearance
    }

    // MARK: - scan confirmation views
    
    private func showConfirmation(for scannedProduct: ScannedProduct, _ scannedCode: String) {
        self.confirmationVisible = true
        self.scanConfirmationView.present(scannedProduct, scannedCode, cart: self.shoppingCart)
        self.displayScanConfirmationView(hidden: false, setBottomOffset: self.productType != .userMustWeigh)
    }
    
    private func displayScanConfirmationView(hidden: Bool, setBottomOffset: Bool = true) {
        guard self.view.window != nil else {
            return
        }
        
        self.confirmationVisible = !hidden
        self.barcodeDetector.reticleVisible = hidden

        if setBottomOffset {
            self.scanConfirmationViewBottom.constant = hidden ? self.hiddenConfirmationOffset : self.visibleConfirmationOffset
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           usingSpringWithDamping: 0.8,
                           initialSpringVelocity: 0,
                           options: .curveEaseInOut,
                           animations: {
                                self.view.layoutIfNeeded()
                           },
                           completion: { _ in })
        }
    }

    func updateCartButton() {
        let items = self.shoppingCart.numberOfItems
        if items > 0 {
            if let total = self.shoppingCart.total {
                let formatter = PriceFormatter(SnabbleUI.project)
                self.barcodeDetector.cartButtonTitle = String(format: "Snabble.Scanner.goToCart".localized(), formatter.format(total))
            } else {
                self.barcodeDetector.cartButtonTitle = "Snabble.Scanner.goToCart.empty".localized()
            }
        } else {
            self.barcodeDetector.cartButtonTitle = nil
        }
    }

    @objc func cartUpdated(_ notification: Notification) {
        self.updateCartButton()
    }
}

// MARK: - message display

extension ScannerViewController {

    private func showMessage(_ msg: String) {
        self.messageLabel.text = msg
        self.messageWrapper.isHidden = false
        self.messageTopDistance.constant = 0
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }

        let millis = min(max(50 * msg.count, 2000), 7000)
        let seconds = TimeInterval(millis) / 1000.0
        self.messageTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            self.hideMessage()
        }
    }

    @objc private func messageTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        self.hideMessage()
    }

    private func hideMessage() {
        self.messageTopDistance.constant = -150

        UIView.animate(withDuration: 0.2,
                       animations: { self.view.layoutIfNeeded() },
                       completion: { _ in self.messageWrapper.isHidden = true })
    }
}

// MARK: - analytics delegate
extension ScannerViewController: AnalyticsDelegate {
    public func track(_ event: AnalyticsEvent) {
        self.delegate.track(event)
    }
}

// MARK: - scanning confirmation delegate
extension ScannerViewController: ScanConfirmationViewDelegate {
    func closeConfirmation(_ item: CartItem?) {
        self.displayScanConfirmationView(hidden: true)
        self.updateCartButton()

        if let msgId = item?.product.scanMessage, let msgText = self.delegate.scanMessageText(for: msgId) {
            let alert = UIAlertController(title: "Snabble.Scanner.multiPack".localized(), message: msgText, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Snabble.OK".localized(), style: .default) { action in
                self.checkRecommendation(item)
            })

            self.present(alert, animated: true)
        } else {
            self.checkRecommendation(item)
        }
    }

    private func checkRecommendation(_ item: CartItem?) {
        guard let item = item else {
            return self.restartScanner()
        }

        self.delegate.showRecommendation(self, SnabbleUI.project, self.shop, item.product) { _ in
            self.restartScanner()
        }
    }

    private func restartScanner() {
        self.lastScannedCode = ""
        self.barcodeDetector.startScanning()
    }
}

// MARK: - scanning view delegate
extension ScannerViewController: BarcodeDetectorDelegate {
    public func enterBarcode() {
        let barcodeEntry = BarcodeEntryViewController(self.productProvider, delegate: self.delegate, completion: self.manuallyEnteredCode)
        self.navigationController?.pushViewController(barcodeEntry, animated: true)
        
        self.barcodeDetector.stopScanning()
    }
    
    public func scannedCode(_ code: String, _ format: ScanFormat) {
        if code == self.lastScannedCode {
            return
        }

        self.handleScannedCode(code)
    }

    public func gotoShoppingCart() {
        self.delegate.gotoShoppingCart()
    }
}

extension ScannerViewController {

    private func scannedUnknown(_ msg: String, _ code: String) {
        // Log.debug("scanned unknown code \(code)")
        self.tapticFeedback.notificationOccurred(.error)

        self.showMessage(msg)
        self.delegate.track(.scanUnknown(code))

        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
            self.lastScannedCode = ""
        }
    }

    private func handleScannedCode(_ scannedCode: String, _ template: String? = nil) {
        // Log.debug("handleScannedCode \(scannedCode) \(self.lastScannedCode)")
        self.lastScannedCode = scannedCode

        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { timer in
            self.spinner.startAnimating()
        }

        self.barcodeDetector.stopScanning()

        self.productForCode(scannedCode, template) { scannedProduct in
            self.timer?.invalidate()
            self.timer = nil
            self.spinner.stopAnimating()

            guard let scannedProduct = scannedProduct else {
                self.scannedUnknown("Snabble.Scanner.unknownBarcode".localized(), scannedCode)
                self.barcodeDetector.startScanning()
                return
            }

            let product = scannedProduct.product
            let embeddedData = scannedProduct.embeddedData

            // check for sale stop
            if product.saleStop {
                self.showSaleStop()
                return
            }

            // handle scanning the shelf code of a pre-weighed product (no data or 0 encoded in the EAN)
            if product.type == .preWeighed && (embeddedData == nil || embeddedData == 0) {
                let msg = "Snabble.Scanner.scannedShelfCode".localized()
                self.scannedUnknown(msg, scannedCode)
                self.barcodeDetector.startScanning()
                return
            }

            self.tapticFeedback.notificationOccurred(.success)

            self.delegate.track(.scanProduct(scannedProduct.transmissionCode ?? scannedCode))
            self.productType = product.type

            if product.bundles.count > 0 {
                self.showBundleSelection(for: scannedProduct, scannedCode)
            } else {
                self.showConfirmation(for: scannedProduct, scannedCode)
            }
        }
    }

    private func showSaleStop() {
        let alert = UIAlertController(title: "Snabble.saleStop.errorMsg.title".localized(), message: "Snabble.saleStop.errorMsg.scan".localized(), preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Snabble.OK".localized(), style: .default) { action in
            self.barcodeDetector.startScanning()
        })
        
        self.present(alert, animated: true)
    }

    private func showBundleSelection(for scannedProduct: ScannedProduct, _ scannedCode: String) {
        let alert = UIAlertController(title: nil, message: "Snabble.Scanner.BundleDialog.headline".localized(), preferredStyle: .actionSheet)

        let product = scannedProduct.product
        alert.addAction(UIAlertAction(title: product.name, style: .default) { action in
            self.showConfirmation(for: scannedProduct, scannedCode)
        })

        for bundle in product.bundles {
            alert.addAction(UIAlertAction(title: bundle.name, style: .default) { action in
                let bundleCode = bundle.codes.first?.code
                let transmissionCode = bundle.codes.first?.transmissionCode ?? bundleCode
                let lookupCode = transmissionCode ?? scannedCode
                let scannedBundle = ScannedProduct(bundle, lookupCode, transmissionCode)
                self.showConfirmation(for: scannedBundle, transmissionCode ?? scannedCode)
            })
        }

        alert.addAction(UIAlertAction(title: "Snabble.Cancel".localized(), style: .cancel) { action in
            self.barcodeDetector.startScanning()
        })

        // HACK: set the action sheet buttons background
        if let alertContentView = alert.view.subviews.first?.subviews.first {
            for view in alertContentView.subviews {
                view.backgroundColor = .white
            }
        }

        self.present(alert, animated: true)
    }

    private func productForCode(_ code: String, _ template: String?, completion: @escaping (ScannedProduct?) -> () ) {
        // if we were given a template from the barcode entry, use that to lookup the product directly
        if let template = template {
            return self.lookupProduct(code, template, nil, completion)
        }

        // check override codes first
        let project = SnabbleUI.project
        if let match = CodeMatcher.matchOverride(code, project.priceOverrideCodes, project.id) {
            return self.productForOverrideCode(match, completion: completion)
        }

        // then, check our regular templates
        let matches = CodeMatcher.match(code, project.id)
        guard matches.count > 0 else {
            return completion(nil)
        }

        let lookupCodes = matches.map { $0.lookupCode }
        let templates = matches.map { $0.template.id }
        let codes = Array(zip(lookupCodes, templates))

        self.productProvider.productByScannableCodes(codes, self.shop.id) { result in
            switch result {
            case .success(let lookupResult):
                guard let parseResult = matches.first(where: { $0.template.id == lookupResult.templateId }) else {
                    completion(nil)
                    return
                }

                let scannedCode = lookupResult.transmissionCode ?? code
                var newResult = ScannedProduct(lookupResult.product,
                                               parseResult.lookupCode,
                                               scannedCode,
                                               lookupResult.templateId,
                                               parseResult.embeddedData,
                                               lookupResult.encodingUnit,
                                               parseResult.referencePrice)

                if let decimalData = parseResult.embeddedDecimal {
                    var encodingUnit = lookupResult.product.encodingUnit
                    var embeddedData: Int? = nil
                    let div = Int(pow(10.0, Double(decimalData.fractionDigits)))
                    if let enc = encodingUnit {
                        switch enc {
                        case .piece:
                            encodingUnit = .piece
                            embeddedData = decimalData.value / div
                        case .kilogram, .meter, .liter, .squareMeter:
                            encodingUnit = enc.fractionalUnit(div)
                            embeddedData = decimalData.value
                        case .gram, .millimeter, .milliliter:
                            embeddedData = decimalData.value
                        default:
                            Log.warn("unspecified conversion for embedded data: \(decimalData.value) \(enc)")
                        }
                    }

                    newResult = ScannedProduct(lookupResult.product, parseResult.lookupCode, scannedCode, lookupResult.templateId, embeddedData, encodingUnit, newResult.referencePriceOverride)
                }

                completion(newResult)
            case .failure:
                let event = AppEvent(scannedCode: code, codes: codes, project: project)
                event.post()
                completion(nil)
            }
        }
    }

    private func productForOverrideCode(_ match: OverrideLookup, completion: @escaping (ScannedProduct?) -> () ) {
        let code = match.lookupCode

        if let template = match.lookupTemplate {
            return self.lookupProduct(code, template, match.embeddedData, completion)
        }

        let matches = CodeMatcher.match(code, SnabbleUI.project.id)

        guard matches.count > 0 else {
            return completion(nil)
        }

        let lookupCodes = matches.map { $0.lookupCode }
        let templates = matches.map { $0.template.id }
        let codes = Array(zip(lookupCodes, templates))
        self.productProvider.productByScannableCodes(codes, self.shop.id) { result in
            switch result {
            case .success(let lookupResult):
                let newResult = ScannedProduct(lookupResult.product, code, match.transmissionCode, lookupResult.templateId, nil, .price, priceOverride: match.embeddedData)
                completion(newResult)
            case .failure:
                completion(nil)
            }
        }
    }

    private func lookupProduct(_ code: String, _ template: String, _ priceOverride: Int?, _ completion: @escaping (ScannedProduct?) -> () ) {
        let codes = [(code, template)]
        self.productProvider.productByScannableCodes(codes, self.shop.id) { result in
            switch result {
            case .success(let lookupResult):
                let transmissionCode = lookupResult.product.codes[0].transmissionCode
                let scannedProduct: ScannedProduct
                if let priceOverride = priceOverride {
                    scannedProduct = ScannedProduct(lookupResult.product, code, transmissionCode, template, nil, .price, nil, priceOverride: priceOverride)
                } else {
                    scannedProduct = ScannedProduct(lookupResult.product, code, transmissionCode, template)
                }
                completion(scannedProduct)
            case .failure:
                completion(nil)
            }
        }
    }

    private func manuallyEnteredCode(_ code: String, _ template: String?) {
        self.handleScannedCode(code, template)
    }

}

extension ScannerViewController: KeyboardHandling {

    func keyboardWillShow(_ info: KeyboardInfo) {
        self.scanConfirmationViewBottom.constant = -(info.keyboardHeight - 48)
        UIView.animate(withDuration: info.animationDuration) {
            self.view.layoutIfNeeded()
        }
    }

    func keyboardWillHide(_ info: KeyboardInfo) {
        self.scanConfirmationViewBottom.constant = self.confirmationVisible ? self.visibleConfirmationOffset : self.hiddenConfirmationOffset
        UIView.animate(withDuration: info.animationDuration) {
            self.view.layoutIfNeeded()
        }
    }

}

extension ScannerViewController: CustomizableAppearance {
    public func setCustomAppearance(_ appearance: CustomAppearance) {
        self.barcodeDetector.setCustomAppearance(appearance)
        self.customAppearance = appearance

        if let titleIcon = appearance.titleIcon {
            let imgView = UIImageView(image: titleIcon)
            self.navigationItem.titleView = imgView
        }
    }
}
