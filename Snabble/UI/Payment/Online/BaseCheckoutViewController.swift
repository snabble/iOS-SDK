//
//  BaseCheckoutViewController.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

import UIKit

public class BaseCheckoutViewController: UIViewController {

    @IBOutlet private weak var stackView: UIStackView!
    @IBOutlet private weak var topWrapper: UIView!
    @IBOutlet private weak var topIcon: UIImageView!
    @IBOutlet private weak var iconHeight: NSLayoutConstraint!
    @IBOutlet private weak var arrowWrapper: UIView!
    @IBOutlet private weak var spinnerWrapper: UIView!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!
    @IBOutlet private weak var codeWrapper: UIView!
    @IBOutlet private weak var codeImage: UIImageView!
    @IBOutlet private weak var codeWidth: NSLayoutConstraint!
    @IBOutlet private weak var idWrapper: UIView!
    @IBOutlet private weak var idLabel: UILabel!
    @IBOutlet private weak var cancelButton: UIButton!

    private let cart: ShoppingCart
    private weak var delegate: PaymentDelegate!
    public weak var navigationDelegate: CheckoutNavigationDelegate?

    private let process: CheckoutProcess
    private let rawJson: [String: Any]?
    private var initialBrightness: CGFloat = 0

    private var sessionTask: URLSessionTask?
    private var processTimer: Timer?

    init(_ process: CheckoutProcess, _ rawJson: [String: Any]?, _ cart: ShoppingCart, _ delegate: PaymentDelegate) {
        self.process = process
        self.rawJson = rawJson
        self.cart = cart
        self.delegate = delegate

        super.init(nibName: "BaseCheckoutViewController", bundle: SnabbleBundle.main)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Snabble.Payment.confirm".localized()

        self.topWrapper.isHidden = true
        self.arrowWrapper.isHidden = true
        SnabbleUI.getAsset(.checkoutOnline, bundlePath: "Checkout/\(SnabbleUI.project.id)/checkout-online") { img in
            if let img = img {
                self.topIcon.image = img
                self.iconHeight.constant = img.size.height
                self.topWrapper.isHidden = false
                self.arrowWrapper.isHidden = false
            }
        }

        self.spinnerWrapper.isHidden = true

        let components = self.process.links.`self`.href.components(separatedBy: "/")
        let id = components.last ?? "n/a"
        self.idLabel.text = String(id.suffix(4))

        let qrCodeContent = self.qrCodeContent(self.process, id)
        self.codeImage.image = QRCode.generate(for: qrCodeContent, scale: 5)
        self.codeWidth.constant = self.codeImage.image?.size.width ?? 0

        self.cancelButton.setTitle("Snabble.Cancel".localized(), for: .normal)
        self.cancelButton.setTitleColor(SnabbleUI.appearance.primaryColor, for: .normal)

        self.navigationItem.hidesBackButton = true

        if !SnabbleUI.implicitNavigation && self.navigationDelegate == nil {
            let msg = "navigationDelegate may not be nil when using explicit navigation"
            assert(self.navigationDelegate != nil, msg)
            Log.error(msg)
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.initialBrightness = UIScreen.main.brightness

        self.cancelButton.alpha = 0
        self.cancelButton.isUserInteractionEnabled = false

        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            UIView.animate(withDuration: 0.2) {
                self.cancelButton.alpha = 1
            }
            self.cancelButton.isUserInteractionEnabled = true
        }

        UIApplication.shared.isIdleTimerDisabled = true

        if self.initialBrightness < 0.5 {
            UIScreen.main.brightness = 0.5
            self.delegate?.track(.brightnessIncreased)
        }

        self.setSpinnerAppearance()

        self.updateQRCode(self.process)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.delegate?.track(self.viewEvent)

        let needsPolling = self.updateView(self.process, self.rawJson)
        if needsPolling {
            self.startTimer()
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UIScreen.main.brightness = self.initialBrightness
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - child classes must override these methods

    func showQrCode(_ process: CheckoutProcess) -> Bool {
        fatalError("child classes must override this")
    }

    func qrCodeContent(_ process: CheckoutProcess, _ id: String) -> String {
        fatalError("child classes must override this")
    }

    var viewEvent: AnalyticsEvent {
        fatalError("child classes must override this")
    }

    // MARK: - polling timer
    private func startTimer() {
        self.processTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            let project = SnabbleUI.project
            self.process.update(project,
                                taskCreated: { self.sessionTask = $0 },
                                completion: { self.update($0) })
        }
    }

    private func stopTimer() {
        self.processTimer?.invalidate()
        self.processTimer = nil

        self.sessionTask?.cancel()
        self.sessionTask = nil
    }

    // MARK: - process updates
    private func update(_ result: RawResult<CheckoutProcess, SnabbleError>) {
        var continuePolling = true
        switch result.result {
        case .success(let process):
            continuePolling = self.updateView(process, result.rawJson)
        case .failure(let error):
            Log.error(String(describing: error))
        }

        if continuePolling {
            self.startTimer()
        }
    }

    // update our view according to the `process`.
    // Return true if we should keep checking the process, false otherwise
    private func updateView(_ process: CheckoutProcess, _ rawJson: [String: Any]?) -> Bool {
        // figure out failure conditions first
        let approvalDenied = process.supervisorApproval == false || process.paymentApproval == false
        let checkFailed = process.checks.first { $0.state == .failed } != nil
        if approvalDenied || checkFailed {
            self.paymentFinished(false, process, rawJson)
            return false
        }

        if let candidateLink = process.paymentResult?["originCandidateLink"] as? String {
            OriginPoller.shared.startPolling(SnabbleUI.project, candidateLink)
        }

        self.updateQRCode(process)

        switch process.paymentState {
        case .successful:
            self.paymentFinished(true, process, rawJson)
            return false
        case .failed:
            self.paymentFinished(false, process, rawJson)
            return false
        case .pending:
            let states = Set(process.fulfillments.map { $0.state })
            if !FulfillmentState.failureStates.isDisjoint(with: states) {
                self.paymentFinished(false, process, rawJson)
                return false
            }
            return true
        case .transferred, .processing, .unknown: ()
            return true
        }
    }

    private func updateQRCode(_ process: CheckoutProcess) {
        let show = self.showQrCode(process)

        self.topWrapper.isHidden = !show
        if self.topIcon.image != nil {
            self.arrowWrapper.isHidden = !show
        }
        self.codeWrapper.isHidden = !show
        self.spinnerWrapper.isHidden = show

        self.stackView.layoutIfNeeded()
    }

    @IBAction private func cancelButtonTapped(_ sender: UIButton) {
        self.delegate?.track(.paymentCancelled)

        self.stopTimer()

        self.process.abort(SnabbleUI.project) { result in
            switch result {
            case .success:
                self.delegate?.track(.paymentCancelled)

                if SnabbleUI.implicitNavigation {
                    if let cartVC = self.navigationController?.viewControllers.first(where: { $0 is ShoppingCartViewController}) {
                        self.navigationController?.popToViewController(cartVC, animated: true)
                    } else {
                        self.navigationController?.popToRootViewController(animated: true)
                    }
                } else {
                    self.navigationDelegate?.checkoutCancelled()
                }
            case .failure:
                let alert = UIAlertController(title: "Snabble.Payment.cancelError.title".localized(),
                                              message: "Snabble.Payment.cancelError.message".localized(),
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Snabble.OK".localized(), style: .default) { _ in

                })
                self.present(alert, animated: true)
            }
        }
    }

    private func paymentFinished(_ success: Bool, _ process: CheckoutProcess, _ rawJson: [String: Any]?) {
        if success {
            self.cart.removeAll(endSession: true, keepBackup: false)

            // poll fulfillments if there are any in a non-finished state
            if !process.fulfillmentsDone() {
                FulfillmentPoller.shared.startPolling(SnabbleUI.project, process)
            }
        }
        self.delegate?.paymentFinished(success, self.cart, process, rawJson)
    }
}

// MARK: - Appearance change
extension BaseCheckoutViewController {
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 13.0, *) {
            guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
                return
            }

            self.setSpinnerAppearance()
        }
    }

    private func setSpinnerAppearance() {
        if #available(iOS 13.0, *) {
            if self.traitCollection.userInterfaceStyle == .dark {
                self.spinner.style = .white
            } else {
                self.spinner.style = .gray
            }
        }
    }
}