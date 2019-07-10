//
//  ShoppingCartTableCell.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import UIKit

protocol ShoppingCartTableDelegate: class {
    func confirmDeletion(at row: Int)
    func updateQuantity(_ quantity: Int, at row: Int)
    var showImages: Bool { get }
}

final class ShoppingCartTableCell: UITableViewCell {

    @IBOutlet private weak var productImage: UIImageView!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!

    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var quantityLabel: UILabel!
    @IBOutlet private weak var priceLabel: UILabel!

    @IBOutlet private weak var minusButton: UIButton!
    @IBOutlet private weak var plusButton: UIButton!

    @IBOutlet private weak var quantityInput: UITextField!
    @IBOutlet private weak var unitsLabel: UILabel!

    @IBOutlet private weak var buttonWrapper: UIView!
    @IBOutlet private weak var weightWrapper: UIView!
    @IBOutlet private weak var imageWrapper: UIView!
    @IBOutlet private weak var imageWrapperWidth: NSLayoutConstraint!
    @IBOutlet private weak var quantityWrapper: UIView!

    private var quantity = 0
    private var item: CartItem?
    private var lineItems = [CheckoutInfo.LineItem]()

    private weak var delegate: ShoppingCartTableDelegate!
    private var task: URLSessionDataTask?
    private var doneButton: UIBarButtonItem?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.minusButton.makeBorderedButton()
        self.plusButton.makeBorderedButton()

        self.priceLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        self.quantityLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        self.quantityLabel.textColor = SnabbleUI.appearance.secondaryColor
        self.quantityLabel.backgroundColor = .clear

        self.quantityWrapper.backgroundColor = SnabbleUI.appearance.primaryColor
        self.quantityWrapper.layer.cornerRadius = 2
        self.quantityWrapper.layer.masksToBounds = true

        self.quantityInput.tintColor = SnabbleUI.appearance.primaryColor
        self.doneButton = self.quantityInput.addDoneButton()
        self.quantityInput.delegate = self

        self.prepareForReuse()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.task?.cancel()
        self.task = nil
        self.productImage.image = nil
        self.imageWrapperWidth.constant = 61

        self.buttonWrapper.isHidden = true
        self.weightWrapper.isHidden = true
        self.imageWrapper.isHidden = true

        self.item = nil
        self.lineItems = []
        self.quantity = 0

        self.quantityLabel.text = nil
        self.nameLabel.text = nil
        self.priceLabel.text = nil
        self.unitsLabel.text = nil
        self.quantityInput.text = nil
    }

    func setLineItem(_ mainItem: CheckoutInfo.LineItem, _ lineItems: [CheckoutInfo.LineItem], row: Int, delegate: ShoppingCartTableDelegate) {
        self.delegate = delegate
        self.item = nil
        self.lineItems = []
        self.quantity = 0

        self.nameLabel.text = mainItem.name

        self.displayLineItemPrice(nil, mainItem, lineItems)

        self.quantityLabel.text = "\(mainItem.amount)"

        self.loadImage()
    }

    func setDiscount(_ amount: Int, delegate: ShoppingCartTableDelegate) {
        self.delegate = delegate

        self.nameLabel.text = "Snabble.Shoppingcart.discounts".localized()
        self.quantityWrapper.isHidden = true

        let formatter = PriceFormatter(SnabbleUI.project)
        self.priceLabel.text = formatter.format(amount)

        self.loadImage()
        if self.delegate.showImages {
            self.imageView?.image = UIImage.fromBundle("icon-percent")
        }
    }

    func setGiveaway(_ lineItem: CheckoutInfo.LineItem, delegate: ShoppingCartTableDelegate) {
        self.delegate = delegate

        self.nameLabel.text = lineItem.name
        self.quantityWrapper.isHidden = true

        self.priceLabel.text = "Snabble.Shoppingcart.giveaway".localized()
        if self.delegate.showImages {
            self.imageView?.image = UIImage.fromBundle("icon-giveaway")
        }
    }

    func setCartItem(_ item: CartItem, _ lineItems: [CheckoutInfo.LineItem], row: Int, delegate: ShoppingCartTableDelegate) {
        self.delegate = delegate
        self.item = item
        self.lineItems = lineItems
        self.quantity = item.quantity

        let product = item.product
        self.nameLabel.text = product.name

        self.minusButton.tag = row
        self.plusButton.tag = row
        self.quantityInput.tag = row

        if item.editable {
            self.buttonWrapper.isHidden = false
        }

        if product.type == .userMustWeigh {
            self.weightWrapper.isHidden = false
            self.buttonWrapper.isHidden = true
        }
        self.quantityInput.text = "\(item.quantity)"

        self.showQuantity()

        var price = item.price
        if let linePrice = lineItems.first(where: { $0.type == .default })?.price {
            price = linePrice
        }

        // suppress display when price == 0
        if price == 0 {
            self.priceLabel.text = ""
            self.buttonWrapper.isHidden = true
        }

        self.loadImage()
    }

    private func updateQuantity(at row: Int, reload: Bool = true) {
        guard let item = self.item else {
            return
        }

        if self.quantity == 0 && item.product.type != .userMustWeigh {
            self.delegate.confirmDeletion(at: row)
            return
        }

        self.item?.quantity = self.quantity
        if reload {
            self.delegate.updateQuantity(self.quantity, at: row)
        }

        // self.lineItems = []
        self.showQuantity()
    }

    private func showQuantity() {
        guard let item = self.item else {
            return
        }

        let showWeight = item.product.referenceUnit?.hasDimension == true || item.product.type == .userMustWeigh
        let encodingUnit = item.encodingUnit ?? item.product.encodingUnit
        let unit = encodingUnit?.display ?? ""
        let unitDisplay = showWeight ? unit : ""

        self.quantityLabel.text = "\(item.effectiveQuantity)\(unitDisplay)"
        self.unitsLabel.text = unitDisplay

        if let defaultItem = lineItems.first(where: { $0.type == .default }) {
            self.displayLineItemPrice(item.product, defaultItem, lineItems)
        } else {
            let formatter = PriceFormatter(SnabbleUI.project)
            self.priceLabel.text = item.priceDisplay(formatter)
        }
    }

    private func displayLineItemPrice(_ product: Product?, _ mainItem: CheckoutInfo.LineItem, _ lineItems: [CheckoutInfo.LineItem]) {
        let formatter = PriceFormatter(SnabbleUI.project)

        if let depositTotal = lineItems.first(where: { $0.type == .deposit })?.totalPrice {
            let single = formatter.format(mainItem.price ?? 0)
            let deposit = formatter.format(depositTotal)
            let total = formatter.format((mainItem.totalPrice ?? 0) + depositTotal)
            self.priceLabel.text = "× \(single) + \(deposit) = \(total)"
        } else {
            let showUnit = product?.referenceUnit?.hasDimension == true || product?.type == .userMustWeigh
            if showUnit {
                let single = formatter.format(mainItem.price ?? 0)
                let unit = product?.referenceUnit?.display ?? ""
                let total = formatter.format(mainItem.totalPrice ?? 0)
                self.priceLabel.text = "× \(single)/\(unit) = \(total)"
            } else {
                if mainItem.amount == 1 {
                    let total = formatter.format(mainItem.totalPrice ?? 0)
                    self.priceLabel.text = "\(total)"
                } else {
                    let single = formatter.format(mainItem.price ?? 0)
                    let total = formatter.format(mainItem.totalPrice ?? 0)
                    self.priceLabel.text = "× \(single) = \(total)"
                }
            }
        }
    }
    
    private func loadImage() {
        guard
            let imgUrl = self.item?.product.imageUrl,
            let url = URL(string: imgUrl)
        else {
            self.imageWrapperWidth.constant = self.delegate.showImages ? 61 : 0
            self.imageWrapper.isHidden = true
            return
        }

        self.imageWrapperWidth.constant = 61
        self.imageWrapper.isHidden = false
        // self.setNeedsLayout()

        self.spinner.startAnimating()

        self.task = URLSession.shared.dataTask(with: url) { data, response, error in
            self.task = nil
            DispatchQueue.main.async() {
                self.spinner.stopAnimating()
            }
            guard let data = data, error == nil else {
                return
            }

            if let image = UIImage(data: data) {
                DispatchQueue.main.async() {
                    self.productImage.image = image
                }
            }
        }
        self.task?.resume()
    }

    @IBAction func minusButtonTapped(_ button: UIButton) {
        if self.quantity > 0 {
            self.quantity -= 1
            self.updateQuantity(at: button.tag)
        }
    }

    @IBAction func plusButtonTapped(_ button: UIButton) {
        if self.item?.product.type == .userMustWeigh {
            // treat this as the "OK" button
            self.quantityInput.resignFirstResponder()
            return
        }
        
        if self.quantity < ShoppingCart.maxAmount {
            self.quantity += 1
            self.updateQuantity(at: button.tag)
        }
    }

}

extension ShoppingCartTableCell: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text as NSString? else {
            return false
        }

        let newText = text.replacingCharacters(in: range, with: string)
        let qty = Int(newText) ?? 0

        self.doneButton?.isEnabled = qty > 0
        if qty > ShoppingCart.maxAmount || (range.location == 0 && string == "0") {
            return false
        }

        self.quantity = qty
        self.updateQuantity(at: textField.tag, reload: false)
        return true
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        self.updateQuantity(at: textField.tag)
        return true
    }

}
