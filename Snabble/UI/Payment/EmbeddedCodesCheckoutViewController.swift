//
//  EmbeddedCodesCheckoutViewController.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit

class EmbeddedCodesCheckoutViewController: UIViewController {

    @IBOutlet weak var explanation1: UILabel!
    @IBOutlet weak var totalPriceLabel: UILabel!
    @IBOutlet weak var explanation2: UILabel!
    @IBOutlet weak var paidButton: UIButton!

    private var initialBrightness: CGFloat = 0

    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var pageControl: UIPageControl!
    private weak var cart: ShoppingCart!
    private weak var delegate: PaymentDelegate!
    private var process: CheckoutProcess?
    private var poller: PaymentProcessPoller?

    private var codeblocks: Codeblocks
    private var codes = [String]()
    private var itemSize = CGSize(width: 100, height: 100)
    private static let defaultCodes = EncodedCodes(prefix: "", separator: "", suffix: "", maxCodes: 100, finalCode: nil, nextCode: nil, nextCodeWithCheck: nil)

    init(_ process: CheckoutProcess?, _ cart: ShoppingCart, _ delegate: PaymentDelegate) {
        self.process = process
        self.cart = cart
        self.delegate = delegate
        self.codeblocks = Codeblocks(SnabbleUI.project.encodedCodes ?? EmbeddedCodesCheckoutViewController.defaultCodes)

        super.init(nibName: nil, bundle: Snabble.bundle)

        self.title = "Snabble.QRCode.title".localized()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.paidButton.backgroundColor = SnabbleUI.appearance.primaryColor
        self.paidButton.makeRoundedButton()
        self.paidButton.setTitle("Snabble.QRCode.didPay".localized(), for: .normal)

        let nib = UINib(nibName: "QRCodeCell", bundle: Snabble.bundle)
        self.collectionView.register(nib, forCellWithReuseIdentifier: "qrCodeCell")

        let codeblocks = Codeblocks(SnabbleUI.project.encodedCodes!)

        let (regularCodes, restrictedCodes) = self.codesForQR()
        self.codes = codeblocks.generateQrCodes(regularCodes, restrictedCodes)

        self.pageControl.numberOfPages = self.codes.count
        self.pageControl.pageIndicatorTintColor = .lightGray
        self.pageControl.currentPageIndicatorTintColor = SnabbleUI.appearance.primaryColor
        self.collectionView.dataSource = self
        self.collectionView.delegate = self

        self.setButtonTitle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.delegate.track(.viewEmbeddedCodesCheckout)

        self.initialBrightness = UIScreen.main.brightness
        if self.initialBrightness < 0.5 {
            UIScreen.main.brightness = 0.5
        }

        let total = PriceFormatter.format(cart.totalPrice)
        self.totalPriceLabel.text = "Snabble.QRCode.total".localized() + "\(total)"
        let explanation = self.codes.count > 1 ? "Snabble.QRCode.showTheseCodes" : "Snabble.QRCode.showThisCode"
        self.explanation1.text = explanation.localized()
        self.explanation2.text = "Snabble.QRCode.priceMayDiffer".localized()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.collectionView.frame.width
        if width != self.itemSize.width {
            self.itemSize = CGSize(width: width, height: width)
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UIScreen.main.brightness = self.initialBrightness
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let process = self.process {
            self.poller = PaymentProcessPoller(process, SnabbleUI.project, self.cart.config.shop)
            self.poller?.waitFor([.receipt]) { events in }
        }
    }

    private func codesForQR() -> ([String],[String]) {
        let project = SnabbleUI.project
        let items = self.cart.items.sorted { $0.itemPrice(project) < $1.itemPrice(project) }

        if self.codeblocks.config.nextCodeWithCheck != nil {
            let regularItems = items.filter { return $0.product.saleRestriction == .none }
            let restrictedItems = items.filter { return $0.product.saleRestriction != .none }

            var regularCodes = self.codesFor(regularItems)
            if let additionalCodes = self.cart.additionalCodes {
                regularCodes.append(contentsOf: additionalCodes)
            }
            let restrictedCodes = self.codesFor(restrictedItems)

            return (regularCodes, restrictedCodes)
        } else {
            var codes = self.codesFor(items)
            if let additionalCodes = self.cart.additionalCodes {
                codes.append(contentsOf: additionalCodes)
            }

            return (codes, [])
        }
    }

    private func codesFor(_ items: [CartItem]) -> [String] {
        return items.reduce(into: [], { result, item in
            if item.product.type == .userMustWeigh {
                // generate an EAN with the embedded weight
                if let template = item.product.weighedItemIds?.first {
                    let ean = EAN13.embedDataInEan(template, data: item.quantity)
                    result.append(ean)
                }
            } else {
                result.append(contentsOf: Array(repeating: item.scannedCode, count: item.quantity))
            }
        })
    }

    private func setButtonTitle() {
        let title = self.pageControl.currentPage == self.codes.count - 1 ? "Snabble.QRCode.didPay" : "Snabble.QRCode.nextCode"
        self.paidButton.setTitle(title.localized(), for: .normal)
    }

    @IBAction func paidButtonTapped(_ sender: UIButton) {
        if self.pageControl.currentPage != self.codes.count - 1 {
            self.pageControl.currentPage += 1
            let indexPath = IndexPath(item: pageControl.currentPage, section: 0)
            self.collectionView.scrollToItem(at: indexPath, at: .left, animated: true)

            self.setButtonTitle()
        } else {
            self.delegate.track(.markEmbeddedCodesPaid)
            self.cart.removeAll(endSession: true)
            NotificationCenter.default.post(name: .snabbleCartUpdated, object: self)

            self.delegate.paymentFinished(true, self.cart)
        }
    }

}

extension EmbeddedCodesCheckoutViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.codes.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "qrCodeCell", for: indexPath) as! QRCodeCell

        let img = self.qrCode(with: self.codes[indexPath.row])
        cell.imageView.image = img
        cell.imageWidth.constant = img?.size.width ?? 0

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return self.itemSize
    }

    private func qrCode(with code: String) -> UIImage? {
        NSLog("QR Code content:\n\(code)")
        for scale in (1...7).reversed() {
            if let img = QRCode.generate(for: code, scale: scale) {
                if img.size.width <= self.collectionView.bounds.width {
                    return img
                }
            }
        }

        return nil
    }

    @IBAction func pageControlTapped(_ pageControl: UIPageControl) {
        if pageControl.currentPage < self.codes.count {
            let indexPath = IndexPath(item: pageControl.currentPage, section: 0)
            self.collectionView.scrollToItem(at: indexPath, at: .left, animated: true)
        }
        self.setButtonTitle()
    }

    // adjust the page control when the scrolling ends
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let newPage = Int((scrollView.contentOffset.x + self.itemSize.width/2) / self.itemSize.width)
        self.pageControl.currentPage = newPage
        self.setButtonTitle()
    }
}
