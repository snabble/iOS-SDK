//
//  ProductDbNetwork.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

extension ProductDB {

    func getSingleProduct(_ url: String, _ placeholder: String, _ identifier: String, completion: @escaping (Product?, Bool) -> () ) {
        self.getSingleProduct(url, placeholder, identifier) { (result: LookupResult?, error: Bool) in
            if let result = result {
                completion(result.product, error)
            } else {
                completion(nil, error)
            }
        }
    }

    func getSingleProduct(_ url: String, _ placeholder: String, _ identifier: String, completion: @escaping (LookupResult?, Bool) -> () ) {
        let session = URLSession(configuration: URLSessionConfiguration.default)

        // TODO: is this the right value?
        let timeoutInterval: TimeInterval = 5

        let fullUrl = url.replacingOccurrences(of: placeholder, with: identifier)
        guard let request = SnabbleAPI.request(.get, fullUrl, timeout: timeoutInterval) else {
            return completion(nil, true)
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let data = data, let response = response as? HTTPURLResponse {
                if response.statusCode == 404 {
                    DispatchQueue.main.async {
                        NSLog("online product lookup with \(placeholder) \(identifier): not found")
                        completion(nil, false)
                    }
                    return
                }

                do {
                    NSLog("online product lookup with \(placeholder) \(identifier) succeeded")
                    let apiProduct = try JSONDecoder().decode(APIProduct.self, from: data)
                    if let depositSku = apiProduct.depositProduct {
                        // get the deposit product
                        if let depositProduct = self.productBySku(depositSku) {
                            // found it locally in db
                            self.completeProduct(apiProduct, depositProduct.price, completion: completion)
                        } else {
                            // get from server
                            self.productBySku(depositSku) { depositProduct, error in
                                if let deposit = depositProduct?.price {
                                    self.completeProduct(apiProduct, deposit, completion: completion)
                                } else {
                                    self.returnError("deposit product not found", completion: completion)
                                }
                            }
                        }
                    } else {
                        // product w/o deposit
                        self.completeProduct(apiProduct, completion: completion)
                    }
                } catch let error {
                    self.returnError("product parse error: \(error)", completion: completion)
                }
            } else {
                self.returnError("error getting product from \(fullUrl): \(String(describing: error))", completion: completion)
            }
        }

        task.resume()
    }

    func getBundlingProducts(_ url: String, _ placeholder: String, _ sku: String, completion: @escaping (_ bundles: [Product], _ error: Bool) -> ()) {
        let session = URLSession(configuration: URLSessionConfiguration.default)

        // TODO: is this the right value?
        let timeoutInterval: TimeInterval = 5

        let fullUrl = url.replacingOccurrences(of: placeholder, with: sku)
        guard let request = SnabbleAPI.request(.get, fullUrl, timeout: timeoutInterval) else {
            return completion([], true)
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let data = data, let response = response as? HTTPURLResponse {
                if response.statusCode == 404 {
                    DispatchQueue.main.async {
                        NSLog("online bundle lookup with \(placeholder) \(sku): not found")
                        completion([], false)
                    }
                    return
                }

                do {
                    // FIXME: parse result once it's no longer a json stream
                }
            }
        }
        task.resume()
    }

    func completeProduct(_ apiProduct: APIProduct, _ deposit: Int? = nil, completion: @escaping (LookupResult?, Bool) -> () ) {
        let matchingCode = apiProduct.matchingCode ?? ""

        self.getBundlingProducts(self.config.lookupBundleUrl, "{sku}", apiProduct.sku) { bundles, error in
            let result = LookupResult(product: apiProduct.convert(deposit, bundles), code: matchingCode)
            DispatchQueue.main.async {
                completion(result, false)
            }
        }
    }

    func returnError(_ msg: String, completion: @escaping (LookupResult?, Bool) -> () ) {
        NSLog(msg)
        DispatchQueue.main.sync {
            completion(nil, true)
        }
    }
}

// this is how we get product data from the lookup endpoints
struct APIProduct: Codable {
    let sku: String
    let name: String
    let description: String?
    let subtitle: String?
    let depositProduct: String?
    let bundledProduct: String?
    let imageUrl: String?
    let productType: APIProductType
    let eans: [String]?
    let price: Int
    let discountedPrice: Int?
    let basePrice: String?
    let weighing: Weighing?
    let saleRestriction: APISaleRestriction?
    let saleStop: Bool?
    let matchingCode: String?

    enum APIProductType: String, Codable {
        case `default`
        case weighable
        case deposit
    }

    enum APISaleRestriction: String, Codable {
        case min_age_6
        case min_age_12
        case min_age_14
        case min_age_16
        case min_age_18
        case min_age_21
        case fsk

        func convert() -> SaleRestriction {
            switch self {
            case .min_age_6: return .age(6)
            case .min_age_12: return .age(12)
            case .min_age_14: return .age(14)
            case .min_age_16: return .age(16)
            case .min_age_18: return .age(18)
            case .min_age_21: return .age(21)
            case .fsk: return .fsk
            }
        }
    }

    struct Weighing: Codable {
        let weighedItemIds: [String]
        let weighByCustomer: Bool
    }

    // convert a JSON representation to our normal model object
    func convert(_ deposit: Int?, _ bundles: [Product]) -> Product {
        var type = ProductType.singleItem
        var weighItemIds: Set<String>?

        if let w = self.weighing {
            type = w.weighByCustomer ? .userMustWeigh : .preWeighed
            weighItemIds = Set(w.weighedItemIds)
        }

        var scannableCodes: Set<String> = Set([])
        if let eans = self.eans {
            scannableCodes = Set(eans)
        }

        return Product(sku: self.sku,
                       name: self.name,
                       description: self.description,
                       subtitle: self.subtitle,
                       imageUrl: self.imageUrl,
                       basePrice: self.basePrice,
                       listPrice: self.price,
                       discountedPrice: self.discountedPrice,
                       type: type,
                       scannableCodes: scannableCodes,
                       weighedItemIds: weighItemIds,
                       depositSku: self.depositProduct,
                       bundledSku: self.bundledProduct,
                       isDeposit: self.productType == .deposit,
                       deposit: deposit,
                       saleRestriction: self.saleRestriction?.convert() ?? .none,
                       saleStop: self.saleStop ?? false,
                       bundles: bundles
        )
    }
}
