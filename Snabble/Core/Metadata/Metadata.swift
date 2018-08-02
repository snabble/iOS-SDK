//
//  Metadata.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

public struct EmbeddedCodesConfig {
    public let prefix: String
    public let suffix: String
    public let separator: String
    public let maxCodes: Int

    public static let edeka = EmbeddedCodesConfig(prefix: "XE", suffix: "XZ", separator: "XE", maxCodes: 30)
    public static let multiline = EmbeddedCodesConfig(prefix: "", suffix: "", separator: "\n", maxCodes: 100)

    public init(prefix: String, suffix: String, separator: String, maxCodes: Int) {
        self.prefix = prefix
        self.suffix = suffix
        self.separator = separator
        self.maxCodes = maxCodes
    }
}


public struct Metadata: Decodable {
    public let flags: Flags
    public let projects: [Project]

    enum CodingKeys: String, CodingKey {
        case flags = "metadata"
        case projects
    }
}

public struct Project: Decodable {
    public let id: String
    public let links: MetadataLinks
    public let rawLinks: [String: Link]

    public let currency: String
    public let decimalDigits: Int
    public let locale: String
    public let pricePrefixes: [String]
    public let unitPrefixes: [String]
    public let weighPrefixes: [String]
    public let roundingMode: RoundingMode
    public let currencySymbol: String // derived from the locale

    public let verifyInternalEanChecksum: Bool
    public let useGermanPrintPrefixes: Bool
    public let qrCodePrefix: String
    public let qrCodeSeparator: String
    public let qrCodeSuffix: String
    public let qrCodeMaxEans: Int

    public let shops: [Shop]

    public var embeddedCodesConfig: EmbeddedCodesConfig {
        return EmbeddedCodesConfig(prefix: self.qrCodePrefix, suffix: self.qrCodeSuffix, separator: self.qrCodeSeparator, maxCodes: self.qrCodeMaxEans)
    }

    enum CodingKeys: String, CodingKey {
        case id, links
        case currency, decimalDigits, locale, pricePrefixes, unitPrefixes, weighPrefixes, roundingMode
        case verifyInternalEanChecksum, useGermanPrintPrefixes, qrCodePrefix, qrCodeSeparator, qrCodeSuffix, qrCodeMaxEans
        case shops
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.links = try container.decode(MetadataLinks.self, forKey: .links)
        self.rawLinks = try container.decode([String: Link].self, forKey: .links)

        self.currency = try container.decode(.currency)
        self.decimalDigits = try container.decode(.decimalDigits)
        self.locale = try container.decode(.locale)
        self.pricePrefixes = try container.decode(.pricePrefixes)
        self.unitPrefixes = try container.decode(.unitPrefixes)
        self.weighPrefixes = try container.decode(.weighPrefixes)
        self.roundingMode = try container.decode(.roundingMode)

        self.verifyInternalEanChecksum = try container.decode(.verifyInternalEanChecksum)
        self.qrCodePrefix = try container.decodeIfPresent(.qrCodePrefix) ?? ""
        self.qrCodeSeparator = try container.decodeIfPresent(.qrCodeSeparator) ?? "\n"
        self.qrCodeSuffix = try container.decodeIfPresent(.qrCodeSuffix) ?? ""
        self.qrCodeMaxEans = try container.decodeIfPresent(.qrCodeMaxEans) ?? 100
        self.useGermanPrintPrefixes = try container.decodeIfPresent(.useGermanPrintPrefixes) ?? false

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: self.locale)
        formatter.currencyCode = self.currency
        formatter.numberStyle = .currency
        self.currencySymbol = formatter.currencySymbol

        self.shops = (try container.decodeIfPresent([Shop].self, forKey: .shops)) ?? []
    }
}

/// Link
public struct Link: Decodable {
    public let href: String

    /// empty instance, used for the default init of `MetadataLinks`
    static let empty = Link(href: "")
}

public struct MetadataLinks: Decodable {
    public let appdb: Link
    public let appEvents: Link
    public let checkoutInfo: Link
    public let productBySku: Link
    public let productByCode: Link
    public let productByWeighItemId: Link
    public let bundlesForSku: Link
    public let productsBySku: Link

    public init() {
        self.appdb = Link.empty
        self.appEvents = Link.empty
        self.checkoutInfo = Link.empty
        self.productBySku = Link.empty
        self.productByCode = Link.empty
        self.productByWeighItemId = Link.empty
        self.bundlesForSku = Link.empty
        self.productsBySku = Link.empty
    }

    public init(appdb: Link, appEvents: Link, checkoutInfo: Link, productBySku: Link, productByCode: Link, productByWeighItemId: Link, bundlesForSku: Link, productsBySku: Link) {
        self.appdb = appdb
        self.appEvents = appEvents
        self.checkoutInfo = checkoutInfo
        self.productBySku = productBySku
        self.productByCode = productByCode
        self.productByWeighItemId = productByWeighItemId
        self.bundlesForSku = bundlesForSku
        self.productsBySku = productsBySku
    }
}

//public struct AppData: Decodable {
//    public let links: MetadataLinks
//    public let flags: Flags
//    public let shops: [Shop]
//    public let rawLinks: [String: Link]
//    public let project: ProjectConfig
//
//    enum CodingKeys: String, CodingKey {
//        case links
//        case flags = "metadata"
//        case shops
//        case project
//    }
//
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        self.links = try container.decode(MetadataLinks.self, forKey: .links)
//        self.flags = try container.decode(Flags.self, forKey: .flags)
//        self.project = try container.decode(ProjectConfig.self, forKey: .project)
//        self.shops = (try container.decodeIfPresent([Shop].self, forKey: .shops)) ?? []
//
//        self.rawLinks = try container.decode([String: Link].self, forKey: .links)
//    }
//}

public struct Flags: Decodable {
    public let kill: Bool
}

public enum RoundingMode: String, Decodable {
    case up
    case down
    case commercial

    ///
    var mode: NSDecimalNumber.RoundingMode {
        switch self {
        case .up: return .up
        case .down: return .down
        case .commercial: return .plain
        }
    }
}

//public struct ProjectConfig: Codable {
//    public let currency: String
//    public let decimalDigits: Int
//    public let locale: String
//    public let pricePrefixes: [String]
//    public let unitPrefixes: [String]
//    public let weighPrefixes: [String]
//    public let roundingMode: RoundingMode
//    public let verifyInternalEanChecksum: Bool
//
//    public let currencySymbol: String
//
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//
//        self.currency = try container.decode(.currency)
//        self.decimalDigits = try container.decode(.decimalDigits)
//        self.locale = try container.decode(.locale)
//        self.pricePrefixes = try container.decodeIfPresent(.pricePrefixes) ?? []
//        self.unitPrefixes = try container.decodeIfPresent(.unitPrefixes) ?? []
//        self.weighPrefixes = try container.decodeIfPresent(.weighPrefixes) ?? []
//        self.roundingMode = try container.decodeIfPresent(.roundingMode) ?? .up
//        self.verifyInternalEanChecksum = try container.decodeIfPresent(.verifyInternalEanChecksum) ?? true
//
//        let formatter = NumberFormatter()
//        formatter.locale = Locale(identifier: self.locale)
//        formatter.currencyCode = self.currency
//        formatter.numberStyle = .currency
//        self.currencySymbol = formatter.currencySymbol
//    }
//
//    internal init(pricePrefixes: [String] = [], weighPrefixes: [String] = [], unitPrefixes: [String] = []) {
//        self.currency = "EUR"
//        self.decimalDigits = 2
//        self.locale = "de_DE"
//        self.pricePrefixes = pricePrefixes
//        self.weighPrefixes = weighPrefixes
//        self.unitPrefixes = unitPrefixes
//        self.roundingMode = .commercial
//        self.verifyInternalEanChecksum = true
//        self.currencySymbol = "€"
//    }
//}

// MARK: - shop data

/// opening hours
public struct OpeningHoursSpecification: Decodable {
    public let opens: String
    public let closes: String
    public let dayOfWeek: String
}

/// base data for one shop
public struct Shop: Decodable {
    /// id of this shop, use this to initialize shopping carts
    public let id: String
    /// name of this shop
    public let name: String
    /// snabble project identifier of this shop
    public let project: String

    /// externally provided identifier
    public let externalId: String?
    /// externally provided data
    public let external: [String: Any]?

    /// latitude
    public let latitude: Double
    /// longitude
    public let longitude: Double

    /// services offered
    public let services: [String]
    /// opening hours
    public let openingHoursSpecification: [OpeningHoursSpecification]

    /// email address
    public let email: String
    /// phone number
    public let phone: String
    /// city
    public let city: String
    /// street
    public let street: String
    /// postal code
    public let postalCode: String
    /// state
    public let state: String
    /// country
    public let country: String

    /// distance to user's current location (in meters)
    public var distance: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, project, externalId, external
        case latitude = "lat", longitude = "lon"
        case services, openingHoursSpecification, email, phone, city, street
        case postalCode = "zip", state, country
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(.id)
        self.name = try container.decode(.name)
        self.project = try container.decode(.project)
        self.externalId = try container.decode(.externalId)
        self.external = try container.decodeIfPresent([String: Any].self, forKey: .external)
        self.latitude = try container.decode(.latitude)
        self.longitude = try container.decode(.longitude)
        self.services = try container.decode(.services)
        self.openingHoursSpecification = try container.decode(.openingHoursSpecification)
        self.email = try container.decode(.email)
        self.phone = try container.decode(.phone)
        self.city = try container.decode(.city)
        self.street = try container.decode(.street)
        self.postalCode = try container.decode(.postalCode)
        self.state = try container.decode(.state)
        self.country = try container.decode(.country)
    }
}

public extension Metadata {

    public static func readResource(_ name: String, extension: String) -> Metadata? {
        if let url = Bundle.main.url(forResource: name, withExtension: `extension`) {
            do {
                let data = try Data(contentsOf: url)
                let metadata = try JSONDecoder().decode(Metadata.self, from: data)
                APIConfig.shared.metadata = metadata
                return metadata
            } catch let error {
                NSLog("error parsing app data resource: \(error)")
            }
        }
        return nil
    }

    public static func load(from url: String, _ parameters: [String: String]? = nil, completion: @escaping (Metadata?) -> () ) {
        guard let request = SnabbleAPI.request(.get, url, parameters: parameters, timeout: 5) else {
            return completion(nil)
        }
        SnabbleAPI.perform(request) { (metadata: Metadata?, error) in
            if let metadata = metadata {
                APIConfig.shared.metadata = metadata
            }
            completion(metadata)
        }
    }

}
