//
//  CartData.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import Foundation

/// data needed to initialize a shopping cart
public struct CartConfig {

    /// directory where the cart should be stored, will be created if it doesn't exist.
    /// Default: the app's "Documents" directory
    public var directory: String

    /// the `Project` that this cart is used in. You must always use the same snabble project for a cart.
    public var project = Project.none

    /// the shop that this cart is used for
    public var shop = Shop.none

    /// the maximum age of a shopping cart, in seconds. Set this to 0 to keep carts forever
    public var maxAge: TimeInterval = 14400

    /// optional: a closure that is used to sort cart items before a QR code is generated
    /// use this to e.g. sort items by price, or move certain item types to the end of the cart
    public typealias ItemSorter = ([CartItem]) -> [CartItem]
    public var sorter: ItemSorter? = nil

    public init() {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = docDir.path
    }
}

/// information about the scanned code that was used to add an item to the
/// shopping cart.
public struct ScannedCode: Codable {
    /// the raw code as seen by the scanner
    public let scannedCode: String
    /// the transmissionCode from the `scannableCodes` table
    public let transmissionCode: String?
    /// embedded data from the scanned code
    public let embeddedData: Int?
    /// encodingUnit from the `scannableCodes` table, overrides the product's if not nil
    public let encodingUnit: Units?
    /// price extracted from the code, e.g. for discount labels at EDEKA
    public let priceOverride: Int?
    /// referencePrice extracted from the code, e.g. at Globus
    public let referencePriceOverride: Int?
    /// template used to parse the code
    public let templateId: String
    /// the lookup code we used to find the product in the database
    public let lookupCode: String

    /// the code we need to transmit to the backend
    public var code: String {
        return self.transmissionCode ?? self.scannedCode
    }

    public init(scannedCode: String, transmissionCode: String? = nil, embeddedData: Int? = nil, encodingUnit: Units? = nil, priceOverride: Int? = nil, referencePriceOverride: Int? = nil, templateId: String, lookupCode: String) {
        self.scannedCode = scannedCode
        self.transmissionCode = transmissionCode
        self.embeddedData = embeddedData
        self.encodingUnit = encodingUnit
        self.priceOverride = priceOverride
        self.referencePriceOverride = referencePriceOverride
        self.templateId = templateId
        self.lookupCode = lookupCode
    }
}

/// an entry in a shopping cart.
public struct CartItem: Codable {
    /// quantity or weight
    internal(set) public var quantity: Int
    /// the product
    public let product: Product
    /// the scanned code
    public let scannedCode: ScannedCode
    /// the rounding mode to use for price calculations
    public let roundingMode: RoundingMode
    /// uuid of this item
    public let uuid: String
    /// optional customer Card no.
    public let customerCard: String?

    public init(_ quantity: Int, _ product: Product, _ scannedCode: ScannedCode, _ customerCard: String?, _ roundingMode: RoundingMode) {
        self.quantity = quantity
        self.product = product
        self.scannedCode = scannedCode
        self.customerCard = customerCard
        self.roundingMode = roundingMode
        self.uuid = UUID().uuidString
    }

    /// init with a freshly retrieved copy of `item.product`.
    init?(updating item: CartItem, _ provider: ProductProvider, _ shopId: String, _ customerCard: String?) {
        guard let product = provider.productBySku(item.product.sku, shopId) else {
            return nil
        }

        self.product = product
        self.quantity = item.quantity
        self.scannedCode = item.scannedCode
        self.customerCard = customerCard
        self.roundingMode = item.roundingMode
        self.uuid = item.uuid
    }

    /// can this entry be merged with another for the same SKU?
    public var canMerge: Bool {
        // yes if it is a single products with a price and we don't have any overrides from the scanned code
        return self.product.type == .singleItem
            && self.product.price(self.customerCard) != 0
            && self.encodingUnit == nil
            && self.scannedCode.priceOverride == nil
            && self.scannedCode.referencePriceOverride == nil
    }

    /// is the quantity user-editable?
    public var editable: Bool {
        // yes if it is a single or user-weighed product, but not if we have data > 0 from the code
        var allowEdit = true
        if let embed = self.scannedCode.embeddedData, embed > 0 {
            allowEdit = false
        }
        if self.scannedCode.priceOverride != nil || self.scannedCode.referencePriceOverride != nil {
            allowEdit = false
        }
        return (self.product.type == .singleItem || self.product.type == .userMustWeigh) && allowEdit
    }

    /// encodingUnit from the code or the product
    public var encodingUnit: Units? {
        return self.scannedCode.encodingUnit ?? self.product.encodingUnit
    }

    /// total price of this cart item
    public var price: Int {
        if let override = self.scannedCode.priceOverride {
            return override
        }
        if let embed = self.scannedCode.embeddedData, let encodingUnit = self.encodingUnit, let referenceUnit = self.product.referenceUnit {
            if case .price = encodingUnit {
                return embed
            }

            let price = self.scannedCode.referencePriceOverride ?? self.product.price(self.customerCard)
            let quantity = max(self.quantity, embed)
            return self.roundedPrice(price, quantity, encodingUnit, referenceUnit)
        }

        if self.product.type == .userMustWeigh {
            // if we get here but have no units, fall back to our previous default of kilograms/grams
            let referenceUnit = product.referenceUnit ?? .kilogram
            let encodingUnit = self.encodingUnit ?? .gram

            return self.roundedPrice(self.product.price(self.customerCard), self.quantity, encodingUnit, referenceUnit)
        }
        return self.quantity * self.product.priceWithDeposit(self.customerCard)
    }

    private func roundedPrice(_ price: Int, _ quantity: Int, _ encodingUnit: Units, _ referenceUnit: Units) -> Int {
        let unitPrice = Units.convert(price, from: encodingUnit, to: referenceUnit)
        let total = Decimal(quantity) * unitPrice

        let roundingHandler = NSDecimalNumberHandler(roundingMode: self.roundingMode.mode,
                                                     scale: 0,
                                                     raiseOnExactness: false,
                                                     raiseOnOverflow: false,
                                                     raiseOnUnderflow: false,
                                                     raiseOnDivideByZero: false)
        return (total as NSDecimalNumber).rounding(accordingToBehavior: roundingHandler).intValue
    }

    /// formatted price display, e.g. for the confirmation dialog and the shopping cart table cell.
    /// returns a String like `"x 2,99€ = 5,98€"`. NB: `quantity` is not part of the string!
    ///
    /// - Parameter formatter: the formatter to use
    /// - Returns: the formatted price
    /// - See Also: `quantityDisplay`
    public func priceDisplay(_ formatter: PriceFormatter) -> String {
        let total = formatter.format(self.price)

        let showUnit = self.product.referenceUnit?.hasDimension == true || self.product.type == .userMustWeigh
        if showUnit {
            let price = self.scannedCode.referencePriceOverride ?? self.product.price(self.customerCard)
            let single = formatter.format(price)
            let unit = self.product.referenceUnit?.display ?? ""
            return "× \(single)/\(unit) = \(total)"
        }

        if let deposit = self.product.deposit {
            let itemPrice = formatter.format(self.product.price(self.customerCard))
            let depositPrice = formatter.format(deposit * self.quantity)
            return "× \(itemPrice) + \(depositPrice) = \(total)"
        }

        if self.effectiveQuantity == 1 {
            return total
        } else {
            let price = self.scannedCode.referencePriceOverride ?? self.scannedCode.priceOverride ?? self.product.price(self.customerCard)
            let single = formatter.format(price)
            return "× \(single) = \(total)"
        }
    }

    /// formatted quantity display, e.g. for the confirmation dialog and the shopping cart table cell.
    /// returns a String like `42g`
    ///
    /// - Returns: the formatted price
    /// - See Also: `priceDisplay`
    public func quantityDisplay() -> String {
        let symbol = self.encodingUnit?.display ?? ""
        return "\(self.effectiveQuantity)\(symbol)"
    }

    /// the effective quantity of this cart item.
    public var effectiveQuantity: Int {
        if let embeddedData = self.scannedCode.embeddedData, embeddedData > 0 {
            if self.product.referenceUnit?.hasDimension == true || self.scannedCode.referencePriceOverride != nil {
                return embeddedData
            }
        }

        return self.quantity
    }

    /// get a copy of this data suitable for transferring to the backend
    var cartItem: BackendCartItem {
        var quantity = self.quantity
        var units: Int? = nil
        var price: Int? = nil
        var weight: Int? = nil
        var code = self.scannedCode.code
        let encodingUnit = self.encodingUnit

        if self.product.type == .userMustWeigh {
            if let newCode = CodeMatcher.createInstoreEan(self.scannedCode.templateId, self.scannedCode.lookupCode, quantity) {
                code = newCode
            }
            weight = quantity
            quantity = 1
        }

        if self.product.type == .preWeighed && self.encodingUnit?.hasDimension == true {
            weight = quantity
            quantity = 1
        }

        if self.product.referenceUnit == .piece && (self.scannedCode.embeddedData == nil || self.scannedCode.embeddedData == 0) {
            if let newCode = CodeMatcher.createInstoreEan(self.scannedCode.templateId, self.scannedCode.lookupCode, quantity) {
                code = newCode
            }
            units = quantity
            quantity = 1
        }

        if let unit = encodingUnit, let embed = self.scannedCode.embeddedData, embed > 0 {
            switch unit {
            case .piece: units = embed
            case .price: price = embed
            default: weight = embed
            }
        }

        if let override = self.scannedCode.priceOverride {
            price = override
        }

        if let refOverride = self.scannedCode.referencePriceOverride {
            price = refOverride
        }

        return BackendCartItem(id: self.uuid,
                               sku: self.product.sku,
                               amount: quantity,
                               scannedCode: code,
                               price: price,
                               weight: weight,
                               units: units,
                               weightUnit: encodingUnit)
    }
}

public struct BackendCartInfo: Codable {
    public let lineItems: [CheckoutInfo.LineItem]
    public let totalPrice: Int
}