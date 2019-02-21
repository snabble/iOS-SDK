//
//  ShoppingCart.swift
//
//  Copyright © 2018 snabble. All rights reserved.
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

    /// the customer's loyalty card, if known
    public var loyaltyCard: String? = nil

    /// the maximum age of a shopping cart, in seconds. Set this to 0 to keep carts forever
    public var maxAge: TimeInterval = 14400

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

    /// the code we need to transmit to the backend
    public var code: String {
        return self.transmissionCode ?? self.scannedCode
    }

    public init(scannedCode: String, transmissionCode: String? = nil, embeddedData: Int? = nil, encodingUnit: Units? = nil, priceOverride: Int? = nil, referencePriceOverride: Int? = nil, templateId: String) {
        self.scannedCode = scannedCode
        self.transmissionCode = transmissionCode
        self.embeddedData = embeddedData
        self.encodingUnit = encodingUnit
        self.priceOverride = priceOverride
        self.referencePriceOverride = referencePriceOverride
        self.templateId = templateId
    }
}

/// return type for the `dataForQR` method -
/// quantity and code sting to be embedded in a QR code
public struct QRCodeData: Equatable {
    public let quantity: Int
    public let code: String

    public init(_ quantity: Int, _ code: String) {
        self.quantity = quantity
        self.code = code
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

    public init(_ quantity: Int, _ product: Product, _ scannedCode: ScannedCode, _ roundingMode: RoundingMode) {
        self.quantity = quantity
        self.product = product
        self.scannedCode = scannedCode
        self.roundingMode = roundingMode
    }

    /// init with a freshly retrieved copy of `item.product`.
    init?(updating item: CartItem, _ provider: ProductProvider, _ shopId: String) {
        guard let product = provider.productBySku(item.product.sku, shopId) else {
            return nil
        }

        self.product = product
        self.quantity = item.quantity
        self.scannedCode = item.scannedCode
        self.roundingMode = item.roundingMode
    }

    /// can this entry be merged with another for the same SKU?
    public var canMerge: Bool {
        // yes if it is a single products with a price and we don't have any overrides from the scanned code
        return self.product.type == .singleItem
            && self.product.price != 0
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

            let price = self.scannedCode.referencePriceOverride ?? self.product.price
            let quantity = max(self.quantity, embed)
            return self.roundedPrice(price, quantity, encodingUnit, referenceUnit)
        }

        if self.product.type == .userMustWeigh {
            // if we get here but have no units, fall back to our previous default of kilograms/grams
            let referenceUnit = product.referenceUnit ?? .kilogram
            let encodingUnit = self.encodingUnit ?? .gram

            return self.roundedPrice(self.product.price, self.quantity, encodingUnit, referenceUnit)
        }
        return self.quantity * self.product.priceWithDeposit
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

    /// data for embedding in a QR code
    public var dataForQR: QRCodeData {
        let cartItem = self.cartItem
        return QRCodeData(cartItem.amount, cartItem.scannedCode)
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
            let price = self.scannedCode.referencePriceOverride ?? self.product.price
            let single = formatter.format(price)
            let unit = self.product.referenceUnit?.display ?? ""
            return "× \(single)/\(unit) = \(total)"
        }

        if let deposit = self.product.deposit {
            let itemPrice = formatter.format(self.product.price)
            let depositPrice = formatter.format(deposit * self.quantity)
            return "× \(itemPrice) + \(depositPrice) = \(total)"
        }

        if self.effectiveQuantity == 1 {
            return total
        } else {
            let price = self.scannedCode.referencePriceOverride ?? self.scannedCode.priceOverride ?? self.product.price
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
            code = CodeMatcher.createInstoreEan(self.scannedCode.templateId, code, quantity) ?? "n/a"
            weight = quantity
            quantity = 1
        }

        if self.product.type == .preWeighed {
            weight = quantity
            quantity = 1
        }

        if self.product.referenceUnit == .piece && (self.scannedCode.embeddedData == nil || self.scannedCode.embeddedData == 0) {
            code = CodeMatcher.createInstoreEan(self.scannedCode.templateId, code, quantity) ?? "n/a"
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

        if self.scannedCode.referencePriceOverride != nil {
            price = self.price
        }

        return BackendCartItem(sku: self.product.sku,
                               amount: quantity,
                               scannedCode: code,
                               price: price,
                               weight: weight,
                               units: units,
                               weightUnit: encodingUnit)
    }

}

/// a ShoppingCart is a collection of CartItem objects
final public class ShoppingCart {
    private(set) public var items = [CartItem]()
    private(set) public var session = ""
    private(set) public var lastSaved: Date?

    /// this is intended mainly for the EmbeddedCodesCheckout - use this to append additional codes
    /// (e.g. special "QR code purchase" marker codes) to the list of scanned codes of this cart
    public var additionalCodes: [String]?

    private var timer: Timer?

    private(set) var config: CartConfig

    public static let maxAmount = 9999

    public init(_ config: CartConfig) {
        self.config = config
        let storage = self.loadCart()
        self.items = storage.items
        self.session = storage.session
    }

    /// check if this cart is outdated (ie. it was last saved more than `config.maxAge` seconds ago)
    public var outdated: Bool {
        return self.isTooOld(self.lastSaved)
    }

    private func isTooOld(_ date: Date?) -> Bool {
        if let date = date, self.config.maxAge > 0 {
            let now = Date.timeIntervalSinceReferenceDate
            return date.timeIntervalSinceReferenceDate < now - self.config.maxAge
        }
        return false
    }

    /// get this cart's `shopId`
    public var shopId: String {
        return self.config.shop.id
    }

    /// add an item. if already present and not weight dependent, increase its quantity
    ///
    /// the newly added (or modified) item is moved to the start of the list
    public func add(_ item: CartItem) {
        defer { self.save() }
        if let index = self.items.firstIndex(where: { $0.product.sku == item.product.sku }) {
            var existing = self.items[index]
            if existing.canMerge {
                existing.quantity += item.quantity
                self.items.remove(at: index)
                self.items.insert(existing, at: 0)
                return
            }
        }

        self.items.insert(item, at: 0)
    }

    /// delete the entry at position `index`
    public func remove(at index: Int) {
        self.items.remove(at: index)
        self.save()
    }

    public func setQuantity(_ quantity: Int, at index: Int) {
        if self.items[index].editable {
            self.items[index].quantity = quantity
        } else {
            Log.warn("ignored attempt to modify quantity of non-editable item, sku=\(self.items[index].product.sku)")
        }
        self.save()
    }

    public func setQuantity(_ quantity: Int, for item: CartItem) {
        if let index = self.items.firstIndex(where: { $0.product.sku == item.product.sku }) {
            self.setQuantity(quantity, at: index)
        } else {
            Log.warn("setQuantity: item not found, sku=\(item.product.sku)")
        }
    }

    /// current quantity. returns 0 if not present or item cannot be merged with others
    public func quantity(of cartItem: CartItem) -> Int {
        if let existing = self.items.first(where: { $0.product.sku == cartItem.product.sku }) {
            return existing.canMerge ? existing.quantity : 0
        }

        return 0
    }

    /// number of separate items in the cart
    public var numberOfItems: Int {
        return items.count
    }

    /// number of products in the cart (sum of all quantities)
    public var numberOfProducts: Int {
        return items.reduce(0) { result, item in
            let count = item.product.type == .singleItem ? item.quantity : 1
            return result + count
        }
    }

    func backendItems() -> [BackendCartItem] {
        return items.map { $0.cartItem }
    }

    /// return the the total price of all products. nil if unknown, i.e. when there are products with unknown prices in the cart
    public var total: Int? {
        var noPrice = false
        let total = self.items.reduce(0) { acc, item in
            let price = item.price
            if price == 0 {
                noPrice = true
            }
            return acc + price
        }
        return noPrice ? nil : total
    }

    /// remove all items from the cart
    public func removeAll(endSession: Bool = false) {
        self.items.removeAll()
        self.save()

        if endSession {
            CartEvent.sessionEnd(self)
            self.session = ""
        }
    }

    /// get this cart's `loyaltyCard`
    public var loyaltyCard: String? {
        get { return self.config.loyaltyCard }
        set { self.config.loyaltyCard = newValue }
    }
}

struct CartStorage: Codable {
    let items: [CartItem]
    let session: String
    var lastSaved: Date?

    init() {
        self.items = []
        self.session = ""
    }

    init(_ shoppingCart: ShoppingCart) {
        self.items = shoppingCart.items
        self.session = shoppingCart.session
        self.lastSaved = shoppingCart.lastSaved
    }
}

// MARK: - Persistence
extension ShoppingCart {

    private func cartUrl() -> URL {
        let url = URL(fileURLWithPath: self.config.directory)
        return url.appendingPathComponent(self.config.project.id + ".json")
    }

    /// persist this shopping cart to disk
    private func save() {
        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: self.config.directory) {
                try fileManager.createDirectory(atPath: self.config.directory, withIntermediateDirectories: true, attributes: nil)
            }

            self.lastSaved = Date()
            if self.session == "" {
                self.session = UUID().uuidString
                CartEvent.sessionStart(self)
            }
            let storage = CartStorage(self)
            let encodedItems = try JSONEncoder().encode(storage)
            try encodedItems.write(to: self.cartUrl(), options: .atomic)
        } catch let error {
            Log.error("error saving cart \(self.config.project.id): \(error)")
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { timer in
            CartEvent.cart(self)
        }
    }

    // load this shoppping cart from disk
    private func loadCart() -> CartStorage {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: self.cartUrl().path) {
            return CartStorage()
        }
        
        do {
            let data = try Data(contentsOf: self.cartUrl())
            let storage = try JSONDecoder().decode(CartStorage.self, from: data)
            if self.isTooOld(storage.lastSaved) {
                return CartStorage()
            }
            return storage
        } catch let error {
            Log.error("error loading cart \(self.config.project.id): \(error)")
            return CartStorage()
        }
    }

    /// update the products in this shopping cart, e.g. after a database update was downloaded
    public func updateProducts() {
        let provider = SnabbleAPI.productProvider(for: self.config.project)
        var newItems = [CartItem]()
        for item in self.items {
            if let newItem = CartItem(updating: item, provider, self.config.shop.id) {
                newItems.append(newItem)
            } else {
                newItems.append(item)
            }
        }
        self.items = newItems
        self.save()
    }

}

extension ShoppingCart {

    func createCart() -> Cart {
        let customerInfo = Cart.CustomerInfo(loyaltyCard: self.loyaltyCard)
        return Cart(session: self.session, shopID: self.shopId, customer: customerInfo, items: self.backendItems())
    }

}

// MARK: send events
struct CartEvent {
    static func sessionStart(_ cart: ShoppingCart) {
        let event = AppEvent(.sessionStart, session: cart.session, project: cart.config.project, shopId: cart.shopId)
        event.post()
    }

    static func sessionEnd(_ cart: ShoppingCart) {
        let event = AppEvent(.sessionEnd, session: cart.session, project: cart.config.project, shopId: cart.shopId)
        event.post()
    }

    static func cart(_ cart: ShoppingCart) {
        let event = AppEvent(cart)
        event.post()
    }

}
