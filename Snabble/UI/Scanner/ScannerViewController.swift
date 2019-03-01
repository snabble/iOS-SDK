//
//  ScannerViewController.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit
import AVFoundation

public protocol ScannerDelegate: AnalyticsDelegate, MessageDelegate {
    func closeScanningView()
}

public final class ScannerViewController: UIViewController {

    @IBOutlet private weak var spinner: UIActivityIndicatorView!

    private var scanningView: ScanningView!
    private var scanConfirmationView: ScanConfirmationView!
    private var scanConfirmationViewBottom: NSLayoutConstraint!
    private var tapticFeedback = UINotificationFeedbackGenerator()

    private var infoView: ScannerInfoView!

    private var productProvider: ProductProvider
    private var shoppingCart: ShoppingCart
    private var shop: Shop

    private var lastScannedCode = ""
    private var confirmationVisible = false
    private var productType: ProductType?
    
    private let hiddenConfirmationOffset: CGFloat = 310
    private let visibleConfirmationOffset: CGFloat = -16

    private var keyboardObserver: KeyboardObserver!
    private var scanFormats = [ScanFormat]()
    private weak var delegate: ScannerDelegate!
    private var timer: Timer?
    private var barcodeDetector: BarcodeDetector?

    public init(_ cart: ShoppingCart, _ shop: Shop, delegate: ScannerDelegate, barcodeDetector: BarcodeDetector? = nil) {
        let project = SnabbleUI.project
        self.productProvider = SnabbleAPI.productProvider(for: project)
        self.shoppingCart = cart
        self.shop = shop
        self.scanFormats = project.scanFormats

        super.init(nibName: nil, bundle: Snabble.bundle)

        self.delegate = delegate
        self.barcodeDetector = barcodeDetector

        self.title = "Snabble.Scanner.title".localized()
        self.tabBarItem.image = UIImage.fromBundle("icon-scan")
        self.navigationItem.title = "Snabble.Scanner.scanningTitle".localized()

        let infoIcon = UIImage.fromBundle("icon-info")?.recolored(with: .white)
        let infoButton = UIBarButtonItem(image: infoIcon, style: .plain, target: self, action: #selector(self.infoButtonTapped(_:)))
        self.navigationItem.leftBarButtonItem = infoButton
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var firstTimeInfoShown: Bool {
        get { return UserDefaults.standard.bool(forKey: "snabble.scanner.firstTimeInfoShown") }
        set { UserDefaults.standard.set(newValue, forKey: "snabble.scanner.firstTimeInfoShown") }
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .black

        self.scanningView = ScanningView()
        self.scanningView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scanningView)
        self.scanningView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.scanningView.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        self.scanningView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        self.scanningView.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true

        self.scanConfirmationView = ScanConfirmationView()
        self.scanConfirmationView.translatesAutoresizingMaskIntoConstraints = false
        self.scanningView.addSubview(self.scanConfirmationView)
        self.scanConfirmationView.leadingAnchor.constraint(equalTo: self.scanningView.leadingAnchor, constant: 16).isActive = true
        self.scanConfirmationView.trailingAnchor.constraint(equalTo: self.scanningView.trailingAnchor, constant: -16).isActive = true
        self.scanConfirmationView.centerXAnchor.constraint(equalTo: self.scanningView.centerXAnchor).isActive = true
        let bottom = self.scanConfirmationView.bottomAnchor.constraint(equalTo: self.scanningView.bottomAnchor)
        bottom.isActive = true
        bottom.constant = self.hiddenConfirmationOffset
        self.scanConfirmationViewBottom = bottom

        self.infoView = ScannerInfoView()
        self.infoView.delegate = self
        self.infoView.translatesAutoresizingMaskIntoConstraints = false
        self.scanningView.addSubview(self.infoView)
        self.infoView.leadingAnchor.constraint(equalTo: self.scanningView.leadingAnchor, constant: 16).isActive = true
        self.infoView.trailingAnchor.constraint(equalTo: self.scanningView.trailingAnchor, constant: -16).isActive = true
        self.infoView.centerXAnchor.constraint(equalTo: self.scanningView.centerXAnchor).isActive = true
        self.infoView.bottomAnchor.constraint(equalTo: self.scanningView.bottomAnchor, constant: -16).isActive = true
        self.infoView.isHidden = self.firstTimeInfoShown

        self.scanningView.setup(with: self.scannerConfig())

        self.scanConfirmationView.delegate = self
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.keyboardObserver = KeyboardObserver(handler: self)

        self.delegate.track(.viewScanner)
        if self.firstTimeInfoShown {
            self.scanningView.initializeCamera()
            self.scanningView.startScanning()
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.scanningView.stopScanning()
        self.displayScanConfirmationView(hidden: true)
        self.infoView?.isHidden = true

        self.keyboardObserver = nil
    }

    private func scannerConfig() -> ScanningViewConfig {
        var config = ScanningViewConfig()

        config.torchButtonTitle = "Snabble.Scanner.torchButton".localized()
        config.torchButtonImage = UIImage.fromBundle("icon-light")?.recolored(with: .white)
        config.enterButtonTitle = "Snabble.Scanner.enterCodeButton".localized()
        config.enterButtonImage = UIImage.fromBundle("icon-entercode")?.recolored(with: .white)
        config.textColor = .white
        config.scanFormats = self.scanFormats
        config.reticleCornerRadius = 3

        config.barcodeDetector = self.barcodeDetector

        self.barcodeDetector?.scanFormats = self.scanFormats
        if self.barcodeDetector != nil && self.barcodeDetector?.delegate == nil {
            self.barcodeDetector?.delegate = self
        }
        config.delegate = self
        return config
    }

    /// reset `shoppingCart` when switching between projects
    public func reset(_ cart: ShoppingCart, _ shop: Shop) {
        let project = SnabbleUI.project
        self.productProvider = SnabbleAPI.productProvider(for: project)
        self.shoppingCart = cart
        self.shop = shop
        self.scanFormats = project.scanFormats
        self.scanningView?.setScanFormats(self.scanFormats)

        // avoid camera permission query if this is called before we've ever been on-screen
        if self.scanningView != nil {
            self.closeConfirmation()
            self.navigationController?.popToRootViewController(animated: false)
        }
    }

    // MARK: - scan confirmation views
    
    private func showConfirmation(for scannedProduct: ScannedProduct, _ scannedCode: String) {
        self.confirmationVisible = true
        self.scanConfirmationView.present(scannedProduct, scannedCode, cart: self.shoppingCart)

        self.scanningView.stopScanning()
        self.displayScanConfirmationView(hidden: false, setBottomOffset: self.productType != .userMustWeigh)
    }
    
    private func displayScanConfirmationView(hidden: Bool, setBottomOffset: Bool = true) {
        guard self.view.window != nil else {
            return
        }
        
        self.confirmationVisible = !hidden
        self.scanningView.bottomBarHidden = !hidden
        self.scanningView.reticleHidden = !hidden

        if setBottomOffset {
            self.scanConfirmationViewBottom.constant = hidden ? self.hiddenConfirmationOffset : self.visibleConfirmationOffset
            UIView.animate(withDuration: 0.12) {
                self.view.layoutIfNeeded()
            }
        }
    }

    @objc func infoButtonTapped(_ sender: Any) {
        if self.confirmationVisible {
            return
        }

        self.showInfo()
    }
}

// MARK: - info delegate
extension ScannerViewController: ScannerInfoDelegate {

    func showInfo() {
        self.scanningView.stopScanning()
        self.infoView.isHidden = false
        self.scanningView.reticleHidden = true
    }

    func close() {
        self.infoView.isHidden = true
        self.firstTimeInfoShown = true
        self.scanningView.reticleHidden = false
        self.scanningView.initializeCamera()
        self.scanningView.startScanning()
    }
}

// MARK: - analytics delegate
extension ScannerViewController: AnalyticsDelegate {
    public func track(_ event: AnalyticsEvent) {
        self.delegate.track(event)
    }
}

extension ScannerViewController: MessageDelegate {
    public func showInfoMessage(_ message: String) {
        self.delegate.showInfoMessage(message)
    }

    public func showWarningMessage(_ message: String) {
        self.delegate.showWarningMessage(message)
    }
}

// MARK: - scanning confirmation delegate
extension ScannerViewController: ScanConfirmationViewDelegate {
    func closeConfirmation() {
        self.displayScanConfirmationView(hidden: true)
        self.scanningView.startScanning()
    }
}

// MARK: - scanning view delegate
extension ScannerViewController: ScanningViewDelegate {
    public func closeScanningView() {
        self.delegate.closeScanningView()
    }

    public func requestCameraPermission(currentStatus: AVAuthorizationStatus) {
        switch currentStatus {
        case .restricted, .denied:
            let msg = "Snabble.Scanner.Camera.allowAccess".localized()
            let alert = UIAlertController(title: "Snabble.Scanner.Camera.accessDenied".localized(), message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Snabble.Cancel".localized(), style: .cancel) { action in
                self.closeScanningView()
            })
            alert.addAction(UIAlertAction(title: "Snabble.Settings".localized(), style: .default) { action in
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                self.closeScanningView()
            })
            self.present(alert, animated: true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.scanningView.startScanning()
                    } else {
                        self.closeScanningView()
                    }
                }
            }
        default:
            assertionFailure("unhandled av auth status \(currentStatus.rawValue)")
            break
        }
    }

    public func noCameraFound() {
        Log.debug("no camera found")
    }

    public func enterBarcode() {
        let barcodeEntry = BarcodeEntryViewController(self.productProvider, delegate: self.delegate, completion: self.manuallyEnteredCode)
        self.navigationController?.pushViewController(barcodeEntry, animated: true)
        
        self.scanningView.stopScanning()
    }
    
    public func scannedCode(_ code: String, _ format: ScanFormat) {
        if code == self.lastScannedCode {
            return
        }

        self.handleScannedCode(code)
    }
}

extension ScannerViewController {

    private func scannedUnknown(_ msg: String, _ code: String) {
        // Log.debug("scanned unknown code \(code)")
        self.tapticFeedback.notificationOccurred(.error)

        self.delegate.showWarningMessage(msg)
        self.delegate.track(.scanUnknown(code))

        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
            self.lastScannedCode = ""
        }
    }

    private func handleScannedCode(_ scannedCode: String) {
        // Log.debug("handleScannedCode \(scannedCode) \(self.lastScannedCode)")
        self.lastScannedCode = scannedCode

        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { timer in
            self.spinner.startAnimating()
        }

        self.scanningView.stopScanning()

        self.productForCode(scannedCode) { scannedProduct in
            self.timer?.invalidate()
            self.timer = nil
            self.spinner.stopAnimating()

            guard let scannedProduct = scannedProduct else {
                self.scannedUnknown("Snabble.Scanner.unknownBarcode".localized(), scannedCode)
                self.scanningView.startScanning()
                return
            }

            let product = scannedProduct.product
            let embeddedData = scannedProduct.embeddedData

            // handle scanning the shelf code of a pre-weighed product (no data or 0 encoded in the EAN)
            if product.type == .preWeighed && (embeddedData == nil || embeddedData == 0) {
                let msg = "Snabble.Scanner.scannedShelfCode".localized()
                self.scannedUnknown(msg, scannedCode)
                self.scanningView.startScanning()
                return
            }
            self.tapticFeedback.notificationOccurred(.success)

            self.delegate.track(.scanProduct(scannedProduct.transmissionCode ?? scannedCode))
            self.productType = product.type
            self.lastScannedCode = ""

            if product.bundles.count > 0 {
                self.showBundleSelection(for: scannedProduct, scannedCode)
            } else {
                self.showConfirmation(for: scannedProduct, scannedCode)
            }
        }
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
                let scannedBundle = ScannedProduct(bundle, transmissionCode)
                self.showConfirmation(for: scannedBundle, transmissionCode ?? scannedCode)
            })
        }

        alert.addAction(UIAlertAction(title: "Snabble.Cancel".localized(), style: .cancel) { action in
            self.scanningView.startScanning()
        })

        // HACK: set the action sheet buttons background
        if let alertContentView = alert.view.subviews.first?.subviews.first {
            for view in alertContentView.subviews {
                view.backgroundColor = .white
            }
        }

        self.scanningView.stopScanning()
        self.present(alert, animated: true)
    }

    private func productForCode(_ code: String, completion: @escaping (ScannedProduct?) -> () ) {
        let project = SnabbleUI.project
        if let match = CodeMatcher.matchOverride(code, project.priceOverrideCodes, project.id) {
            return self.productForOverrideCode(match, completion: completion)
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
                let parseResult = matches.first { $0.template.id == lookupResult.templateId }
                let scannedCode = lookupResult.transmissionCode ?? code
                var newResult = ScannedProduct(lookupResult.product, scannedCode, lookupResult.templateId, parseResult?.embeddedData, lookupResult.encodingUnit, parseResult?.referencePrice)

                if let decimalData = parseResult?.embeddedDecimal {
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
                        default: ()
                        }
                    }

                    newResult = ScannedProduct(lookupResult.product, scannedCode, lookupResult.templateId, embeddedData, encodingUnit, newResult.referencePriceOverride)
                }

                completion(newResult)
            case .failure:
                completion(nil)
            }
        }
    }

    private func productForOverrideCode(_ match: OverrideLookup, completion: @escaping (ScannedProduct?) -> () ) {
        let code = match.lookupCode
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
                let newResult = ScannedProduct(lookupResult.product, match.transmissionCode, "ean13_instore", nil, .price, priceOverride: match.embeddedData)
                completion(newResult)
            case .failure:
                completion(nil)
            }
        }
    }

    private func manuallyEnteredCode(_ code: String?) {
        // Log.debug("entered \(code)")
        if let code = code {
            self.handleScannedCode(code)
        }
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
