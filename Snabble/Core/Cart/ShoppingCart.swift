//
//  ShoppingCart.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import Foundation

/// data needed to initialize a shopping cart
public struct CartConfig {

    /// name of the cart.
    public var name = "default"

    /// directory where the cart should be stored, will be created if it doesn't exist.
    /// Default: the app's "Documents" directory
    public var directory: String

    /// a `ProductProvider` instance to use for resolving SKUs to `Product`s. You must always use the same snabble project for a cart.
    public weak var productProvider: ProductProvider?

    /// url for the "create checkout info" endpoint
    public var checkoutInfoUrl = ""

    /// id of the shop that this cart is used for
    public var shopId = "unknown"

    /// the customer's loyalty card, if known
    public var loyaltyCard: String? = nil

    /// the maximum age of a shopping cart, in seconds. Set this to 0 to keep carts forever
    public var maxAge: TimeInterval = 14400

    public init() {
        self.directory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    }
}

/// an entry in a shopping cart.
public struct CartItem: Codable {
    public var quantity: Int
    public let product: Product
    public let scannedCode: String

    // optional data extracted from the scanned code
    let price: Int?
    let weight: Int?
    let units: Int?

    init(_ quantity: Int, _ product: Product, _ scannedCode: String) {
        self.product = product
        self.quantity = quantity
        self.scannedCode = scannedCode

        let ean = EAN.parse(scannedCode)
        self.price = ean?.embeddedPrice
        self.weight = ean?.embeddedWeight
        self.units = ean?.embeddedUnits
    }

    /// total price for this cart item
    public var total: Int {
        if let price = self.price {
            return price
        } else if let units = self.units {
            let multiplier = units == 0 ? self.quantity : units
            return multiplier * self.product.priceWithDeposit
        } else if let weight = self.weight {
            return self.product.priceFor(weight)
        }
        return self.product.priceFor(self.quantity)
    }

    func cartItem() -> Cart.Item {
        let product = self.product
        var quantity = self.quantity
        var weight = self.weight
        if product.type == .userMustWeigh {
            quantity = 1
            weight = self.quantity
        }
        return Cart.Item(sku: product.sku,
                         amount: quantity,
                         scannedCode: self.scannedCode,
                         price: self.price,
                         weight: weight,
                         units: self.units)
    }
}

/// a ShoppingCart is a collection of CartItem objects
public class ShoppingCart {
    
    public static let maxAmount = 9999

    /// this is intended mainly for the EmbeddedCodesCheckout - use this to append additional codes
    /// (e.g. special "QR code purchase" marker codes) to the list of scanned codes of this cart
    public var additionalCodes: [String]?

    private(set) public var items = [CartItem]()
    private(set) public var session = ""
    private(set) public var lastSaved: Date?

    private var timer: Timer?

    private(set) var config: CartConfig

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
        return self.config.shopId
    }

    /// get this cart's `loyaltyCard`
    public var loyaltyCard: String? {
        return self.config.loyaltyCard
    }

    /// get this cart's `createInfoUrl`
    public var checkoutInfoUrl: String {
        return self.config.checkoutInfoUrl
    }

    /// add a Product. if already present and not weight dependent, increase its quantity
    ///
    /// the newly added (or modified) product is moved to the start of the list
    public func add(_ product: Product, quantity: Int = 1, scannedCode: String) {
        let ean = EAN.parse(scannedCode)
        if let index = self.indexOf(product), product.type == .singleItem, ean?.hasEmbeddedData == false {
            var item = self.items[index]
            item.quantity += quantity
            self.items.remove(at: index)
            self.items.insert(item, at: 0)
        } else {
            let item = CartItem(quantity, product, scannedCode)
            self.items.insert(item, at: 0)
        }

        self.save()
    }

    /// get the `CartItem` at `index`
    public func at(_ index: Int) -> CartItem {
        return self.items[index]
    }

    public func product(at index: Int) -> Product? {
        return self.items[index].product
    }
    
    /// change the quantity of the item at  `index`
    public func setQuantity(_ quantity: Int, at index: Int) {
        self.items[index].quantity = quantity

        self.save()
    }

    /// change the quantity for the given product
    public func setQuantity(_ quantity: Int, for product: Product) {
        if let index = self.indexOf(product) {
            self.setQuantity(quantity, at: index)
        }
    }

    /// delete the entry at position `index`
    public func remove(at index: Int) {
        self.items.remove(at: index)

        self.save()
    }

    /// delete a Product entry if it exists
    public func removeProduct(_ product: Product) {
        if let index = self.indexOf(product) {
            self.remove(at: index)
        }
    }

    /// get the quantity of `product` in the cart.
    public func quantity(of product: Product) -> Int {
        if let index = self.indexOf(product) {
            return self.items[index].quantity
        }
        return 0
    }
    
    /// rearrange order: move the entry at `from` to `to`
    public func moveEntry(from: Int, to: Int) {
        let item = self.items[from]
        self.items.remove(at: from)
        self.items.insert(item, at: to)

        self.save()
    }
    
    /// return the number of separate items
    public var count:  Int {
        return self.items.count
    }

    /// return the the total price of all products
    public var totalPrice: Int {
        return self.items.reduce(0) { $0 + $1.total }
    }
    
    /// return the total number of items
    public func numberOfItems() -> Int {
        return self.items.reduce(0) {
            let qty = $1.product.weightDependent ? 1 :  $1.quantity
            return $0 + qty
        }
    }

    /// get all products from this list
    public func allProducts() -> [Product] {
        return (0 ..< self.items.count).compactMap { self.product(at: $0) }
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

    private func indexOf(_ product: Product) -> Int? {
        return self.items.index { $0.product.sku == product.sku }
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
        let path = self.config.directory + "/" + self.config.name + ".json"
        return URL(fileURLWithPath: path)
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
            NSLog("error saving cart \(self.config.name): \(error)")
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
            NSLog("error loading cart \(self.config.name): \(error)")
            return CartStorage()
        }
    }
}

extension ShoppingCart {

    func createCart() -> Cart {
        let items = self.items.map { $0.cartItem() }
        let customerInfo = Cart.CustomerInfo(loyaltyCard: self.loyaltyCard)
        return Cart(session: self.session, shopID: self.shopId, customer: customerInfo, items: items)
    }

}

// MARK: send events
struct CartEvent {
    static func sessionStart(_ cart: ShoppingCart) {
        let event = AppEvent(.sessionStart, session: cart.session, shopId: cart.shopId)
        event.post()
    }

    static func sessionEnd(_ cart: ShoppingCart) {
        let event = AppEvent(.sessionEnd, session: cart.session, shopId: cart.shopId)
        event.post()
    }

    static func cart(_ cart: ShoppingCart) {
        let event = AppEvent(cart)
        event.post()
    }

}
