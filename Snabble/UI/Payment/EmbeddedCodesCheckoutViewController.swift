//
//  EmbeddedCodesCheckoutViewController.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import UIKit

final class EmbeddedCodesCheckoutViewController: UIViewController {

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
    private var qrCodeConfig: QRCodeConfig

    private var codes = [String]()
    private var itemSize = CGSize(width: 100, height: 100)

    init(_ process: CheckoutProcess?, _ cart: ShoppingCart, _ delegate: PaymentDelegate, _ codeConfig: QRCodeConfig) {
        self.process = process
        self.cart = cart
        self.delegate = delegate

        self.qrCodeConfig = codeConfig

        super.init(nibName: nil, bundle: SnabbleBundle.main)

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
        self.paidButton.alpha = 0
        self.paidButton.isUserInteractionEnabled = false

        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { timer in
            UIView.animate(withDuration: 0.2) {
                self.paidButton.alpha = 1
            }
            self.paidButton.isUserInteractionEnabled = true
        }

        let nib = UINib(nibName: "QRCodeCell", bundle: SnabbleBundle.main)
        self.collectionView.register(nib, forCellWithReuseIdentifier: "qrCodeCell")

        self.codes = Codeblocks.generateQrCodes(self.cart, self.qrCodeConfig)

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

        let formatter = PriceFormatter(SnabbleUI.project)

        // if we have a valid checkoutInfo, use the total from that, else what we've calculated in the cart
        let lineItems = self.process?.checkoutInfo.lineItems.count ?? 0
        let total = lineItems > 0 ? self.process?.checkoutInfo.price.price : self.cart.total

        let formattedTotal = formatter.format(total ?? 0)

        self.totalPriceLabel.text = "Snabble.QRCode.total".localized() + "\(formattedTotal)"

        let explKey = self.codes.count > 1 ? "Snabble.QRCode.showTheseCodes" : "Snabble.QRCode.showThisCode"
        let explanation = explKey.localized()

        self.explanation1.text = String(format: explanation, self.codes.count)
        self.explanation2.text = "Snabble.QRCode.priceMayDiffer".localized()

        if total == nil {
            self.totalPriceLabel.isHidden = true
            self.explanation2.isHidden = true
        }
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

    private func setButtonTitle() {
        var title = ""
        if self.pageControl.currentPage == self.codes.count - 1 {
            title = "Snabble.QRCode.didPay".localized()
        } else {
            title = String(format: "Snabble.QRCode.nextCode".localized(),
                           self.pageControl.currentPage+2, self.codes.count)
        }
        self.paidButton.setTitle(title, for: .normal)
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

            self.delegate.paymentFinished(true, self.cart, self.process)
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
        Log.debug("QR Code content:\n\(code)")
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
