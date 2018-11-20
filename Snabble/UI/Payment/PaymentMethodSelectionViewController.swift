//
//  PaymentMethodSelectionViewController.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit

public struct PaymentMethodData {
    public let displayName: String
    public let encryptedData: String

    public init(_ displayName: String, _ encryptedData: String) {
        self.displayName = displayName
        self.encryptedData = encryptedData
    }
}

public enum PaymentMethod {
    case cash
    case qrCode
    case encodedCodes
    case teleCashDeDirectDebit(PaymentMethodData)

    var rawMethod: RawPaymentMethod {
        switch self {
        case .cash: return .cash
        case .qrCode: return .qrCode
        case .encodedCodes: return .encodedCodes
        case .teleCashDeDirectDebit: return .teleCashDeDirectDebit
        }
    }

    var displayName: String? {
        return self.data?.displayName
    }

    var data: PaymentMethodData? {
        switch self {
        case .teleCashDeDirectDebit(let data): return data
        default: return nil
        }
    }
}

class PaymentMethodSelectionViewController: UIViewController {

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    
    private weak var cart: ShoppingCart!
    private var process: PaymentProcess
    private var signedCheckoutInfo: SignedCheckoutInfo
    private var paymentMethods: [PaymentMethod]
    private var itemSize = CGSize.zero

    init(_ process: PaymentProcess, _ paymentMethods: [PaymentMethod]) {
        self.process = process
        self.signedCheckoutInfo = process.signedCheckoutInfo
        self.cart = process.cart
        self.paymentMethods = paymentMethods

        super.init(nibName: nil, bundle: Snabble.bundle)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        self.title = "Snabble.PaymentSelection.title".localized()
        
        super.viewDidLoad()

        self.view.backgroundColor = SnabbleUI.appearance.secondaryColor
        self.titleLabel.textColor = SnabbleUI.appearance.primaryColor

        let totalPrice = PriceFormatter.format(self.signedCheckoutInfo.checkoutInfo.price.price)
        self.titleLabel.text = String(format: "Snabble.PaymentSelection.howToPay".localized(), totalPrice)

        let nib = UINib(nibName: "PaymentMethodCell", bundle: Snabble.bundle)
        self.collectionView.register(nib, forCellWithReuseIdentifier: "paymentCell")
    }

    override func viewDidLayoutSubviews() {
        super .viewDidLayoutSubviews()

        let width = self.collectionView.frame.width - 32
        self.itemSize = CGSize(width: width, height: 96)

        self.updateContentInset()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if self.paymentMethods.count == 1 {
            self.startPayment(self.paymentMethods[0])
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.process.track(.viewPaymentMethodSelection)
    }

    private func updateContentInset() {
        let numRows = self.paymentMethods.count
        var contentInsetTop = self.collectionView.bounds.size.height

        for i in 0 ..< numRows {
            let attributes = self.collectionView.layoutAttributesForItem(at: IndexPath(item: i, section: 0))
            let rowRect = attributes?.frame ?? CGRect.zero
            contentInsetTop -= rowRect.size.height + 10
            if contentInsetTop <= 0 {
                contentInsetTop = 0
            }
        }
        self.collectionView.contentInset = UIEdgeInsets.init(top: contentInsetTop, left: 0, bottom: 0, right: 0)
        if contentInsetTop == 0 {
            // scroll so that the last entry is fully visible
            let last = IndexPath(item: numRows-1, section: 0)
            self.collectionView.scrollToItem(at: last, at: .bottom, animated: false)
        }
    }

    fileprivate func startPayment(_ method: PaymentMethod) {
        self.process.start(method) { viewController, error in
            if let vc = viewController {
                self.navigationController?.pushViewController(vc, animated: true)
            } else {
                let handled = self.process.delegate.handlePaymentError(error)
                if !handled {
                    self.process.delegate.showWarningMessage("Snabble.Payment.errorStarting".localized())
                }
            }
        }
    }

}

// MARK: - collection view delegates
extension PaymentMethodSelectionViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.paymentMethods.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "paymentCell", for: indexPath) as! PaymentMethodCell

        let paymentMethod = self.paymentMethods[indexPath.row]
        cell.icon.image = UIImage.fromBundle(paymentMethod.icon)
        cell.label.text = paymentMethod.displayName

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return self.itemSize
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let paymentMethod = self.paymentMethods[indexPath.row]

        self.startPayment(paymentMethod)
    }
}
