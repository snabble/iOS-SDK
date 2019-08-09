//
//  ShoppingCart.swift
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

/// a ShoppingCart is a collection of CartItem objects
final public class ShoppingCart: Codable {
    private(set) public var items: [CartItem]
    private(set) public var session: String
    private(set) public var lastSaved: Date?
    private(set) public var backendCartInfo: BackendCartInfo?

    public let projectId: String
    public let shopId: String

    internal var checkoutInfoTask: URLSessionDataTask?

    fileprivate var backupItems: [CartItem]?
    fileprivate var backupSession: String?

    public var customerCard: String? {
        didSet {
            self.updateProducts(self.customerCard)
        }
    }

    internal var eventTimer: Timer?

    // number of seconds to wait after a local modification is sent to the backend
    private let saveDelay: TimeInterval = 1.0

    private let maxAge: TimeInterval
    private let directory: String?

    public static let maxAmount = 9999

    enum CodingKeys: String, CodingKey {
        case items, session, lastSaved, backendCartInfo, projectId, shopId, backupItems, backupSession, customerCard, maxAge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decode(.items)
        self.session = try container.decode(.session)
        self.lastSaved = try container.decodeIfPresent(.lastSaved)
        self.backendCartInfo = try container.decodeIfPresent(.backendCartInfo)
        self.projectId = try container.decode(.projectId)
        self.shopId = try container.decode(.shopId)
        self.backupItems = try container.decodeIfPresent(.backupItems)
        self.backupSession = try container.decodeIfPresent(.backupSession)
        self.customerCard = try container.decodeIfPresent(.customerCard)
        self.maxAge = try container.decode(.maxAge)
        self.directory = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.items, forKey: .items)
        try container.encode(self.session, forKey: .session)
        try container.encodeIfPresent(self.lastSaved, forKey: .lastSaved)
        try container.encodeIfPresent(self.backendCartInfo, forKey: .backendCartInfo)
        try container.encode(self.projectId, forKey: .projectId)
        try container.encode(self.shopId, forKey: .shopId)
        try container.encodeIfPresent(self.backupItems, forKey: .backupItems)
        try container.encodeIfPresent(self.backupSession, forKey: .backupSession)
        try container.encodeIfPresent(self.customerCard, forKey: .customerCard)
        try container.encode(self.maxAge, forKey: .maxAge)
    }

    public init(_ config: CartConfig) {
        assert(config.project.id != "", "empty projects cannot have a shopping cart")
        self.projectId = config.project.id
        self.shopId = config.shop.id
        self.maxAge = config.maxAge
        self.directory = config.directory

        self.session = ""
        self.items = []

        if let savedCart = self.load() {
            self.items = savedCart.items
            self.session = savedCart.session
            self.customerCard = savedCart.customerCard

            self.backupItems = savedCart.backupItems
            self.backupSession = savedCart.backupSession
            self.backendCartInfo = savedCart.backendCartInfo
        }
    }

    /// check if this cart is outdated (ie. it was last saved more than `config.maxAge` seconds ago)
    public var outdated: Bool {
        if let lastSaved = self.lastSaved, self.maxAge > 0 {
            let now = Date.timeIntervalSinceReferenceDate
            return lastSaved.timeIntervalSinceReferenceDate < now - self.maxAge
        }
        return false
    }

    /// add an item. if already present and not weight dependent, increase its quantity
    ///
    /// the newly added (or modified) item is moved to the start of the list
    public func add(_ item: CartItem) {
        if self.items.count == 0 {
            self.backupItems = nil
            self.backupSession = nil
        }
        
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
        return self.items.count
    }

    /// number of products in the cart (sum of all quantities)
    public var numberOfProducts: Int {
        return self.items.reduce(0) { result, item in
            let count = item.product.type == .singleItem ? item.quantity : 1
            return result + count
        }
    }

    func backendItems() -> [BackendCartItem] {
        return self.items.map { $0.cartItem }
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
        self.backupItems = self.items
        self.backupSession = self.session

        self.items.removeAll()
        self.save()
        NotificationCenter.default.post(name: .snabbleCartUpdated, object: self)

        if endSession {
            CartEvent.sessionEnd(self)
            self.session = ""
        }
    }

    public func restoreCart() {
        guard
            let backupItems = self.backupItems,
            backupItems.count > 0,
            self.items.count == 0
        else {
            return
        }

        self.items = backupItems
        if let backupSession = self.backupSession {
            self.session = backupSession
        }
        self.backupItems = nil
        self.backupSession = nil
    }

    public var backupAvailable: Bool {
        return (self.backupItems?.count ?? 0) > 0
    }

    /// update the products in this shopping cart, e.g. after a database update was downloaded
    /// or when the customer card was changed
    public func updateProducts(_ customerCard: String? = nil) {
        guard let project = SnabbleAPI.projectFor(self.projectId) else {
            return
        }

        let provider = SnabbleAPI.productProvider(for: project)
        var newItems = [CartItem]()
        for item in self.items {
            if let newItem = CartItem(updating: item, provider, self.shopId, customerCard) {
                newItems.append(newItem)
            } else {
                newItems.append(item)
            }
        }
        self.items = newItems
        self.save()
    }
}

// MARK: - Persistence
extension ShoppingCart {

    private func cartUrl(_ directory: String) -> URL {
        let url = URL(fileURLWithPath: directory)
        return url.appendingPathComponent(self.projectId + ".json")
    }

    /// persist this shopping cart to disk
    private func save(postEvent: Bool = true) {
        guard let directory = self.directory else {
            return
        }

        if postEvent {
            self.backendCartInfo = nil
        }

        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: directory) {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            }

            self.lastSaved = Date()
            if self.session == "" {
                self.session = UUID().uuidString
                CartEvent.sessionStart(self)
            }

            let data = try JSONEncoder().encode(self)
            try data.write(to: self.cartUrl(directory), options: .atomic)
        } catch let error {
            Log.error("error saving cart \(self.projectId): \(error)")
        }

        if postEvent {
            self.eventTimer?.invalidate()
            self.eventTimer = Timer.scheduledTimer(withTimeInterval: self.saveDelay, repeats: false) { timer in
                CartEvent.cart(self)
            }
        }
    }

    // load this shoppping cart from disk
    private func load() -> ShoppingCart? {
        guard let directory = self.directory else {
            return nil
        }

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: self.cartUrl(directory).path) {
            return nil
        }

        do {
            let data = try Data(contentsOf: self.cartUrl(directory))
            let cart = try JSONDecoder().decode(ShoppingCart.self, from: data)
            if cart.outdated {
                return nil
            }
            return cart
        } catch let error {
            Log.error("error loading cart \(self.projectId): \(error)")
            return nil
        }
    }
}

public extension Notification.Name {
    static let snabbleCartUpdated = Notification.Name("snabbleCartUpdated")
}

// MARK: backend connection
extension ShoppingCart {
    func createCart() -> Cart {
        let customerInfo = Cart.CustomerInfo(loyaltyCard: self.customerCard)
        return Cart(session: self.session, shopID: self.shopId, customer: customerInfo, items: self.backendItems())
    }

    func createCheckoutInfo(userInitiated: Bool = false, completion: @escaping (Bool) -> ()) {
        guard let project = SnabbleAPI.projectFor(self.projectId) else {
            completion(false)
            return
        }

        self.createCheckoutInfo(project, timeout: 2) { result in
            switch result {
            case .failure(let error):
                Log.warn("createCheckoutInfo failed: \(error)")
                self.backendCartInfo = nil
                completion(false)
            case .success(let info):
                let session = info.checkoutInfo.session
                Log.info("createCheckoutInfo succeeded: \(session)")
                let totalPrice = info.checkoutInfo.price.price
                self.backendCartInfo = BackendCartInfo(lineItems: info.checkoutInfo.lineItems, totalPrice: totalPrice)
                self.save(postEvent: false)
                completion(true)
            }
            if !userInitiated {
                NotificationCenter.default.post(name: .snabbleCartUpdated, object: self)
            }
        }
    }
}

// MARK: send events
struct CartEvent {
    static func sessionStart(_ cart: ShoppingCart) {
        guard cart.shopId != "" else {
            return
        }

        guard let project = SnabbleAPI.projectFor(cart.projectId) else {
            return
        }

        let event = AppEvent(.sessionStart, session: cart.session, project: project, shopId: cart.shopId)
        event.post()
    }

    static func sessionEnd(_ cart: ShoppingCart) {
        guard cart.shopId != "" else {
            return
        }

        guard let project = SnabbleAPI.projectFor(cart.projectId) else {
            return
        }

        let event = AppEvent(.sessionEnd, session: cart.session, project: project, shopId: cart.shopId)
        event.post()
    }

    static func cart(_ cart: ShoppingCart) {
        if cart.shopId == "" || (cart.items.count == 0 && cart.session == "") {
            return
        }

        cart.createCheckoutInfo(completion: {_ in})
        let event = AppEvent(cart)
        event?.post()
    }
}
