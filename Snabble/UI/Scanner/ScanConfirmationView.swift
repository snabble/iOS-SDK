//
//  ScanConfirmationView.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit

protocol ScanConfirmationViewDelegate: AnalyticsDelegate {
    func closeConfirmation()
    func gotoCheckout()
}

public extension Notification.Name {
    static let snabbleCartUpdated = Notification.Name("snabbleCartUpdated")
}

class ScanConfirmationView: DesignableView {
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var productNameLabel: UILabel!
    @IBOutlet private weak var originalPriceLabel: UILabel!
    @IBOutlet private weak var priceLabel: UILabel!

    @IBOutlet private weak var stackView: UIStackView!
    @IBOutlet private weak var quantityField: UITextField!
    @IBOutlet private weak var minusButton: UIButton!
    @IBOutlet private weak var plusButton: UIButton!
    @IBOutlet private weak var gramLabel: UILabel!

    @IBOutlet private weak var closeButton: UIButton!
    @IBOutlet private weak var cartButton: UIButton!
    @IBOutlet private weak var checkoutButton: UIButton!

    weak var delegate: ScanConfirmationViewDelegate!

    private var product: Product!
    private var alreadyInCart = false
    private var quantity = 1
    private var ean: EANCode!
    
    private weak var shoppingCart: ShoppingCart!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.view.backgroundColor = .clear
        self.addCornersAndShadow(backgroundColor: .white, cornerRadius: 8)

        self.cartButton.backgroundColor = SnabbleAppearance.shared.config.primaryColor
        self.cartButton.tintColor = SnabbleAppearance.shared.config.secondaryColor
        self.cartButton.makeRoundedButton()

        let mono14 = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        self.priceLabel.font = mono14
        self.checkoutButton.titleLabel?.font = mono14
        self.checkoutButton.titleLabel?.adjustsFontSizeToFitWidth = true
        self.checkoutButton.titleLabel?.minimumScaleFactor = 0.5

        self.minusButton.makeBorderedButton()
        self.plusButton.makeBorderedButton()

        self.quantityField.font = UIFont.monospacedDigitSystemFont(ofSize: 21, weight: .regular)
        self.quantityField.tintColor = SnabbleAppearance.shared.config.primaryColor
        self.quantityField.delegate = self

        self.closeButton.setImage(UIImage.fromBundle("icon-close"), for: .normal)
        self.plusButton.setImage(UIImage.fromBundle("icon-plus"), for: .normal)
        self.minusButton.setImage(UIImage.fromBundle("icon-minus"), for: .normal)
    }
    
    func present(_ product: Product, cart: ShoppingCart, ean: EANCode) {
        // avoid ugly animations
        UIView.performWithoutAnimation {
            self.doPresent(product, cart: cart, ean: ean)
            self.layoutIfNeeded()
        }
    }

    private func doPresent(_ product: Product, cart: ShoppingCart, ean: EANCode) {
        self.product = product
        self.productNameLabel.text = product.name
        self.shoppingCart = cart
        self.ean = ean

        self.quantity = 1

        if product.type == .singleItem {
            let cartQuantity = self.shoppingCart.quantity(of: product)
            self.quantity = cartQuantity + 1
            self.alreadyInCart = cartQuantity > 0
        }

        let initialQuantity = ean.embeddedWeight ?? self.quantity

        self.minusButton.isHidden = product.weightDependent
        self.plusButton.isHidden = product.weightDependent
        self.gramLabel.isHidden = !product.weightDependent
        self.quantityField.isEnabled = product.type != .preWeighed
        self.quantityField.isHidden = false

        self.subtitleLabel.text = product.subtitle

        if product.type == .userMustWeigh {
            self.quantityField.becomeFirstResponder()
        }
        if product.type == .singleItem {
            self.addDoneButton()
        } else {
            self.quantityField.inputAccessoryView = nil
        }

        self.showQuantity(initialQuantity, updateTextField: true)

        let cartTitle = self.alreadyInCart ? "Snabble.Scanner.updateCart" : "Snabble.Scanner.addToCart"
        self.cartButton.setTitle(cartTitle.localized(), for: .normal)

        if product.discountedPrice != nil {
            let originalPrice = Price.format(product.listPrice)
            let str = NSAttributedString(string: originalPrice, attributes: [NSAttributedStringKey.strikethroughStyle: NSUnderlineStyle.styleSingle.rawValue])
            self.originalPriceLabel.attributedText = str
        } else {
            self.originalPriceLabel.text = nil
        }
    }
    
    private func showQuantity(_ quantity: Int, updateTextField: Bool) {
        var qty = quantity
        if quantity < 1 && self.product.type != .userMustWeigh {
            qty = 1
        } else if self.quantity > ShoppingCart.maxAmount {
            qty = ShoppingCart.maxAmount
        }

        if updateTextField {
            self.quantityField.text = qty == 0 ? "" : "\(qty)"
        }

        self.cartButton.isEnabled = qty > 0
        self.minusButton.isEnabled = qty > 1
        self.plusButton.isEnabled = qty < ShoppingCart.maxAmount

        var productPrice = 0
        if let weight = self.ean.embeddedWeight {
            productPrice = product.priceFor(weight)
            let priceKilo = Price.format(product.price)
            let formattedPrice = Price.format(productPrice)
            self.priceLabel.text = "\(qty)g × \(priceKilo)/kg = \(formattedPrice)"
        } else if let price = self.ean.embeddedPrice {
            productPrice = price
            self.priceLabel.text = Price.format(productPrice)
            self.quantityField.isHidden = true
            self.gramLabel.isHidden = true
        } else if let amount = self.ean.embeddedUnits {
            let multiplier = amount == 0 ? self.quantity : amount
            productPrice = self.product.priceWithDeposit * multiplier
            self.priceLabel.text = Price.format(productPrice)
            self.quantityField.isHidden = true
            self.gramLabel.isHidden = true
            self.minusButton.isHidden = amount > 0
            self.minusButton.isHidden = amount > 0
            self.quantityField.isHidden = amount > 0
        } else {
            productPrice = self.product.priceFor(qty)
            self.priceLabel.text = Price.format(productPrice)
        }

        let cartTotal = self.alreadyInCart ? 0 : self.shoppingCart.totalPrice
        let newTotal = productPrice + cartTotal

        let totalPrice = Price.format(newTotal)
        let checkoutTitle = String(format: "Snabble.Scanner.gotoCheckout".localized(), totalPrice)

        UIView.performWithoutAnimation {
            self.checkoutButton.setTitle(checkoutTitle, for: .normal)
            self.checkoutButton.layoutIfNeeded()
        }
    }

    func addDoneButton() {
        let keyboardToolbar = UIToolbar()
        keyboardToolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(UITextField.endEditing(_:)))
        keyboardToolbar.items = [ flexSpace, doneButton ]
        self.quantityField.inputAccessoryView = keyboardToolbar
    }

    @IBAction private func plusTapped(_ button: UIButton) {
        self.quantity += 1
        self.showQuantity(self.quantity, updateTextField: true)
    }

    @IBAction private func minusTapped(_ button: UIButton) {
        self.quantity -= 1
        self.showQuantity(self.quantity, updateTextField: true)
    }

    @IBAction private func cartTapped(_ button: UIButton) {
        let cart = self.shoppingCart!
        if cart.quantity(of: self.product) == 0 || self.product.type != .singleItem {
            cart.add(self.product, quantity: self.quantity, scannedCode: self.ean.code)
        } else {
            cart.setQuantity(self.quantity, for: self.product)
        }

        NotificationCenter.default.post(name: .snabbleCartUpdated, object: self)
        self.delegate.closeConfirmation()

        self.quantityField.resignFirstResponder()
    }

    @IBAction private func checkoutTapped(_ button: UIButton) {
        self.cartTapped(button)
        self.delegate.gotoCheckout()
    }

    @IBAction private func closeButtonTapped(_ button: UIButton) {
        self.quantityField.resignFirstResponder()
        self.delegate.track(.scanAborted(self.product.sku))
        self.delegate.closeConfirmation()
    }

}

extension ScanConfirmationView: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text as NSString? else {
            return false
        }

        let newText = text.replacingCharacters(in: range, with: string)
        let qty = Int(newText) ?? 0

        if qty > ShoppingCart.maxAmount || (range.location == 0 && string == "0") {
            return false
        }

        self.quantity = qty
        self.showQuantity(qty, updateTextField: false)

        return true
    }

}
