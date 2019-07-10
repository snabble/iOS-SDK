//
//  CheckoutData.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import Foundation

/// Signed Checkout Info
public struct SignedCheckoutInfo: Decodable {
    public let checkoutInfo: CheckoutInfo
    public let signature: String
    public let links: CheckoutLinks

    enum CodingKeys: String, CodingKey {
        case checkoutInfo
        case signature
        case links
    }

    public struct CheckoutLinks: Decodable {
        public let checkoutProcess: Link

        fileprivate init() {
            self.checkoutProcess = Link.empty
        }
    }

    // not part of the Snabble API, only used internally
    var rawJson: [String: Any]? = nil

    // only used for the embedded codes offline payment
    init() {
        self.checkoutInfo = CheckoutInfo()
        self.signature = ""
        self.links = CheckoutLinks()
    }
}

// known payment methods
public enum RawPaymentMethod: String, CaseIterable {
    case qrCodePOS              // QR Code with a reference to snabble's backend
    case encodedCodes           // QR Code with EANs and separators
    case deDirectDebit          // SEPA direct debit via Telecash/First Data
    case encodedCodesCSV        // QR Code with CSV
    case encodedCodesIKEA       // QR Code for IKEA
    case creditCardVisa         // VISA via Telecash/First Data
    case creditCardMastercard   // MASTERCARD via Telecash/First Data

    /// true if this method reqires additional data, like an IBAN or a credit card number
    public var dataRequired: Bool {
        switch self {
        case .deDirectDebit, .creditCardVisa, .creditCardMastercard:
            return true
        case .qrCodePOS, .encodedCodes, .encodedCodesCSV, .encodedCodesIKEA:
            return false
        }
    }

    /// true if this method can be used even if creating a checkout info/process fails
    public var offline: Bool {
        switch self {
        case .encodedCodes, .encodedCodesCSV, .encodedCodesIKEA:
            return true
        case .qrCodePOS, .deDirectDebit, .creditCardVisa, .creditCardMastercard:
            return false
        }
    }
}

// associated data for a payment method
public struct PaymentMethodData {
    public let displayName: String
    public let encryptedData: String

    public init(_ displayName: String, _ encryptedData: String) {
        self.displayName = displayName
        self.encryptedData = encryptedData
    }
}

// payment method with associated data
public enum PaymentMethod {
    case qrCodePOS
    case encodedCodes
    case deDirectDebit(PaymentMethodData?)
    case encodedCodesCSV
    case encodedCodesIKEA
    case visa(PaymentMethodData?)
    case mastercard(PaymentMethodData?)

    public var rawMethod: RawPaymentMethod {
        switch self {
        case .qrCodePOS: return .qrCodePOS
        case .encodedCodes: return .encodedCodes
        case .deDirectDebit: return .deDirectDebit
        case .encodedCodesCSV: return .encodedCodesCSV
        case .encodedCodesIKEA: return .encodedCodesIKEA
        case .visa: return .creditCardVisa
        case .mastercard: return .creditCardMastercard
        }
    }

    public var data: PaymentMethodData? {
        switch self {
        case .deDirectDebit(let data), .visa(let data), .mastercard(let data):
             return data
        case .qrCodePOS, .encodedCodes, .encodedCodesCSV, .encodedCodesIKEA:
            return nil
        }
    }

    public var displayName: String? {
        return self.data?.displayName
    }
}

public enum PaymentState: String, Decodable {
    case unknown

    case pending
    case processing
    case transferred
    case successful
    case failed
}

extension PaymentState: UnknownCaseRepresentable {
    public static let unknownCase = PaymentState.unknown
}

/// line items can be added by the backend. if they refer back to a shopping cart item via their `refersTo` property, the `type` describes the relationsip
public enum LineItemType: String, Codable {
    /// not actually sent by the backend
    case unknown

    /// default item
    case `default`

    /// this item contains information about deposits, e.g. for a crate of beer
    case deposit

    /// a price-reducing promotion like "1 € off"
    case discount

    /*
    /// a giveaway product that is automatically added - no support yet
    case giveaway
    */
}

extension LineItemType: UnknownCaseRepresentable {
    public static let unknownCase = LineItemType.unknown
}

// CheckoutInfo
public struct CheckoutInfo: Decodable {
    /// session id
    public let session: String
    /// available payment methods, as delivered by the API
    public let availableMethods: [String]
    /// line items (only contains records with supported types)
    public let lineItems: [LineItem]
    /// price info
    public let price: Price

    public struct LineItem: Codable {
        public let id: String
        public let sku: String
        public let name: String
        public let amount: Int
        public let price: Int?
        public let totalPrice: Int?
        public let scannedCode: String?
        public let type: LineItemType
        public let refersTo: String?
    }

    public struct Price: Decodable {
        public let price: Int

        fileprivate init() {
            self.price = 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case session, availableMethods, lineItems, price
    }

    /// available and implemented payment methods
    public var paymentMethods: [RawPaymentMethod] {
        return availableMethods.compactMap { RawPaymentMethod(rawValue: $0) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.session = try container.decode(String.self, forKey: .session)
        self.availableMethods = try container.decode([String].self, forKey: .availableMethods)
        let lineItems = try container.decode([LineItem].self, forKey: .lineItems)
        self.lineItems = lineItems.filter { $0.type != .unknown }
        self.price = try container.decode(Price.self, forKey: .price)
    }

    fileprivate init() {
        self.price = Price()
        self.availableMethods = [ RawPaymentMethod.encodedCodes.rawValue ]
        self.session = ""
        self.lineItems = []
    }
}

/// Checkout Process
public struct CheckoutProcess: Decodable {
    public let links: ProcessLinks
    public let supervisorApproval: Bool?
    public let paymentApproval: Bool?
    public let aborted: Bool
    public let checkoutInfo: CheckoutInfo
    public let paymentMethod: String
    public let modified: Bool
    public let paymentInformation: PaymentInformation?
    public let paymentState: PaymentState
    public let orderID: String?

    public struct ProcessLinks: Decodable {
        public let `self`: Link
        public let approval: Link
        public let receipt: Link?
    }

    public struct PaymentInformation: Decodable {
        /// for method == .qrCodePOS
        public let qrCodeContent: String?
    }
}

// MARK: - data we send to the server

/// Cart
struct Cart: Encodable {
    let session: String
    let shopID: String
    let customer: CustomerInfo?
    let items: [Item]

    struct Item: Encodable {
        let id: String
        let sku: String
        let amount: Int
        let scannedCode: String

        let price: Int?
        let weight: Int?
        let units: Int?
        let weightUnit: Units?
    }

    struct CustomerInfo: Encodable {
        let loyaltyCard: String

        init?(loyaltyCard: String?) {
            guard let c = loyaltyCard else {
                return nil
            }
            self.loyaltyCard = c
        }
    }
}

typealias BackendCartItem = Cart.Item

/// AbortRequest
struct AbortRequest: Encodable {
    let aborted: Bool
}
