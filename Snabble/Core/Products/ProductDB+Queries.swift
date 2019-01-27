//
//  ProductDB+Queries.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import Foundation
import GRDB


// MARK: - low-level db queries
extension ProductDB {

    static let productQuery = """
        select
            p.*, 0 as listPrice, null as discountedPrice, null as basePrice,
            null as code_encodingUnit,
            (select group_concat(sc.code) from scannableCodes sc where sc.sku = p.sku) as codes,
            (select group_concat(sc.template) from scannableCodes sc where sc.sku = p.sku) as templates,
            (select group_concat(ifnull(sc.encodingUnit, "")) from scannableCodes sc where sc.sku = p.sku) as encodingUnits,
            (select group_concat(ifnull(sc.transmissionCode, "")) from scannableCodes sc where sc.sku = p.sku) as transmissionCodes
        from products p
        """

    static let productQueryUnits = """
        select
            p.*, 0 as listPrice, null as discountedPrice, null as basePrice,
            s.encodingUnit as code_encodingUnit,
            (select group_concat(sc.code) from scannableCodes sc where sc.sku = p.sku) as codes,
            (select group_concat(sc.template) from scannableCodes sc where sc.sku = p.sku) as templates,
            (select group_concat(ifnull(sc.encodingUnit, "")) from scannableCodes sc where sc.sku = p.sku) as encodingUnits,
            (select group_concat(ifnull(sc.transmissionCode, "")) from scannableCodes sc where sc.sku = p.sku) as transmissionCodes
        from products p
        join scannableCodes s on s.sku = p.sku
        where s.code = ? and s.template = ?
        """

    func productBySku(_ dbQueue: DatabaseQueue, _ sku: String, _ shopId: String?) -> Product? {
        do {
            let row = try dbQueue.inDatabase { db in
                return try self.fetchOne(db, ProductDB.productQuery + " where p.sku = ?", arguments: [sku])
            }
            return self.productFromRow(dbQueue, row, shopId)
        } catch {
            self.logError("productBySku db error: \(error)")
        }
        return nil
    }

    func productsBySku(_ dbQueue: DatabaseQueue, _ skus: [String], _ shopId: String?) -> [Product] {
        do {
            let list = skus.map { "\"\($0)\"" }.joined(separator: ",")
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, ProductDB.productQuery + " where p.sku in (\(list))")
            }
            return rows.compactMap { self.productFromRow(dbQueue, $0, shopId) }
        } catch {
            self.logError("productsBySku db error: \(error)")
        }
        return []
    }

    func discountedProducts(_ dbQueue: DatabaseQueue, _ shopId: String?) -> [Product] {
        do {
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, ProductDB.productQuery + " " + """
                    left outer join prices pr1 on pr1.sku = p.sku and pr1.pricingCategory = ifnull((select pricingCategory from shops where shops.id = ?), 0)
                    left outer join prices pr2 on pr2.sku = p.sku and pr2.pricingCategory = 0
                    where p.imageUrl is not null and ifnull(pr1.discountedPrice, pr2.discountedPrice) is not null
                    """, arguments: [shopId])
                }
            return rows.compactMap { self.productFromRow(dbQueue, $0, shopId) }
        } catch {
            self.logError("discountedProducts db error: \(error)")
        }
        return []
    }

    func productByScannableCodes(_ dbQueue: DatabaseQueue, _ codes: [(String, String)], _ shopId: String?, retry: Bool = false) -> ScannedProduct? {
        for (code, template) in codes {
            if let result = self.productByScannableCode(dbQueue, code, template, shopId) {
                return result
            }
        }

        return nil
    }

    private func productByScannableCode(_ dbQueue: DatabaseQueue, _ code: String, _ template: String, _ shopId: String?, retry: Bool = false) -> ScannedProduct? {
        do {
            let row = try dbQueue.inDatabase { db in
                return try self.fetchOne(db, ProductDB.productQueryUnits, arguments: [code, template])
            }
            if let product = self.productFromRow(dbQueue, row, shopId) {
                let codeEntry = product.codes.first { $0.code == code }
                let transmissionCode = codeEntry?.transmissionCode
                return ScannedProduct(product, transmissionCode, template)
            } else if !retry {
                // initial lookup failed

                // if it was an EAN-8, try again with the same EAN padded to an EAN-13
                // if it was an EAN-13 with a leading "0", try again with all leading zeroes removed
                if code.count == 8 {
                    Log.debug("8->13 lookup attempt \(code) -> 00000\(code)")
                    return self.productByScannableCode(dbQueue, "00000" + code, template, shopId, retry: true)
                } else if code.first == "0", let codeInt = Int(code) {
                    Log.debug("no leading zeroes db lookup attempt \(code) -> \(codeInt)")
                    return self.productByScannableCode(dbQueue, String(codeInt), template, shopId, retry: true)
                }
            }
        } catch {
            self.logError("productByScannableCode db error: \(error)")
        }

        return nil
    }

    func productsByName(_ dbQueue: DatabaseQueue, _ name: String, _ filterDeposits: Bool) -> [Product] {
        do {
            let limit = name.count < 5 ? name.count * 100 : -1
            let depositCondition = filterDeposits ? "and isDeposit = 0" : ""
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, ProductDB.productQuery + " " + """
                    where p.sku in (select sku from searchByName where foldedName match ? limit ?) \(depositCondition)
                    """, arguments: [name + "*", limit])
            }
            return rows.compactMap { self.productFromRow(dbQueue, $0, nil) }
        } catch {
            self.logError("productsByName db error: \(error)")
        }
        return []
    }

    func productsByScannableCodePrefix(_ dbQueue: DatabaseQueue, _ prefix: String, _ filterDeposits: Bool) -> [Product] {
        do {
            let limit = 100 //  prefix.count < 5 ? prefix.count * 100 : -1
            let depositCondition = filterDeposits ? "and isDeposit = 0" : ""
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, ProductDB.productQuery + " " + """
                    join scannableCodes s on s.sku = p.sku
                    where s.template = "default" and (s.code glob ? or s.code glob ?) \(depositCondition) and p.weighing != \(ProductType.preWeighed.rawValue)
                    limit ?
                    """, arguments: [prefix + "*", "00000" + prefix + "*", limit])
            }
            return rows.compactMap { self.productFromRow(dbQueue, $0, nil) }
        } catch {
            self.logError("productByScannableCodePrefix db error: \(error)")
        }
        return []
    }

    func productsBundling(_ dbQueue: DatabaseQueue, _ sku: String, _ shopId: String?) -> [Product] {
        do {
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, ProductDB.productQuery + " " + """
                    where p.bundledSku = ?
                    """, arguments: [sku])
            }
            return rows.compactMap { self.productFromRow(dbQueue, $0, shopId) }
        } catch {
            self.logError("productsBundling db error: \(error)")
        }
        return []
    }

    func metadata(_ dbQueue: DatabaseQueue) -> [String: String] {
        do {
            let rows = try dbQueue.inDatabase { db in
                return try self.fetchAll(db, "select * from metadata")
            }

            let tuples = rows.compactMap { ($0["key"], $0["value"]) as? (String, String) }
            return Dictionary(uniqueKeysWithValues: tuples)
        } catch {
            self.logError("metadata db error: \(error)")
        }
        return [:]
    }

    func createFullTextIndex(_ dbQueue: DatabaseQueue) throws {
        let start = Date.timeIntervalSinceReferenceDate
        try dbQueue.inDatabase { db in
            try db.execute("drop table if exists searchByName_tmp")
            try db.execute("create virtual table searchByName_tmp using fts4(sku text, foldedname text)")

            let rows = try Row.fetchCursor(db, "select sku, name from products")

            try db.inTransaction {
                while let row = try rows.next() {
                    guard let sku = row["sku"] as? String, let name = row["name"] as? String else {
                        continue
                    }

                    let foldedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    try db.execute("insert into searchByName_tmp values(?, ?)", arguments: [ sku, foldedName ])
                }
                return .commit
            }

            try db.execute("drop table if exists searchByName")
            try db.execute("alter table searchByName_tmp rename to searchByName")
            try db.execute("vacuum")
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - start
        Log.debug("update took \(elapsed)")
    }

    private func productFromRow(_ dbQueue: DatabaseQueue, _ row: Row?, _ shopId: String?) -> Product? {
        guard
            let row = row,
            let sku = row["sku"] as? String
        else {
            return nil
        }

        // if we have a shopId, get the price
        let priceRow: Row
        if let shopId = shopId, let pRow = self.getPriceRowForSku(dbQueue, sku, shopId) {
            priceRow = pRow
        } else {
            priceRow = row
        }

        // find deposit SKU
        let depositSku = row["depositSku"] as? String

        var depositPrice: Int?
        if let dSku = depositSku, let depositProduct = self.productBySku(dbQueue, dSku, shopId) {
            depositPrice = depositProduct.price
        }

        let bundles = self.productsBundling(dbQueue, sku, shopId)

        let codes = self.buildCodes(row["codes"], row["templates"], row["transmissionCodes"], rawUnits: row["encodingUnits"])

        let referenceUnit = Unit.from(row["referenceUnit"] as? String)
        var encodingUnit = Unit.from(row["encodingUnit"] as? String)
        if let encodingOverride = Unit.from(row["code_encodingUnit"] as? String) {
            encodingUnit = encodingOverride
        }

        let p = Product(sku: sku,
                        name: row["name"],
                        description: row["description"],
                        subtitle: row["subtitle"],
                        imageUrl: row["imageUrl"],
                        basePrice: priceRow["basePrice"],
                        listPrice: priceRow["listPrice"],
                        discountedPrice: priceRow["discountedPrice"],
                        type: ProductType(rawValue: row["weighing"]) ?? .singleItem,
                        codes: codes,
                        depositSku: depositSku,
                        bundledSku: row["bundledSku"],
                        isDeposit: row["isDeposit"] == 1,
                        deposit: depositPrice,
                        saleRestriction: SaleRestriction(row["saleRestriction"]),
                        saleStop: row["saleStop"] ?? false,
                        bundles: bundles,
                        referenceUnit: referenceUnit,
                        encodingUnit: encodingUnit)

        return p
    }

    private func getPriceRowForSku(_ dbQueue: DatabaseQueue, _ sku: String, _ shopId: String) -> Row? {
        do {
            let row = try dbQueue.inDatabase { db in
                return  try self.fetchOne(db, """
                        select * from prices where pricingCategory = ifnull((select pricingCategory from shops where shops.id = ?), '0') and sku = ?
                        """, arguments: [shopId, sku])
            }
            if row != nil {
                return row
            }
            let row2 = try dbQueue.inDatabase { db in
                return  try self.fetchOne(db, """
                        select * from prices where pricingCategory = 0 and sku = ?
                        """, arguments: [sku])
            }
            return row2
        } catch {
            self.logError("getPriceRowForSku db error: \(error)")
        }
        return nil
    }

    private func buildCodes(_ rawCodes: String?, _ rawTemplates: String?, _ rawTransmits: String?, rawUnits: String?) -> [ScannableCode] {
        guard let rawCodes = rawCodes, let rawTransmits = rawTransmits, let rawTemplates = rawTemplates, let rawUnits = rawUnits  else {
            return []
        }

        let codes = rawCodes.components(separatedBy: ",")
        let templates = rawTemplates.components(separatedBy: ",")
        let transmits = rawTransmits.components(separatedBy: ",")
        let units = rawUnits.components(separatedBy: ",")

        assert(codes.count == templates.count); assert(codes.count == transmits.count); assert(codes.count == units.count);

        var scannableCodes = [ScannableCode]()
        for i in 0 ..< codes.count {
            let transmissionCode = transmits[i].count == 0 ? nil : transmits[i]
            let c = ScannableCode(codes[i], templates[i], transmissionCode, Unit.from(units[i]))
            scannableCodes.append(c)
        }
        return scannableCodes
    }

    // timing-logging wrappers around Row.fecthOne/fetchAll

    private func fetchOne(_ db: Database, _ query: String, arguments: StatementArguments? = nil) throws -> Row? {
        let start = Date.timeIntervalSinceReferenceDate
        defer {
            self.logSlowQuery(db, query, arguments, start)
        }
        return try Row.fetchOne(db, query, arguments: arguments, adapter: nil)
    }

    private func fetchAll(_ db: Database, _ query: String, arguments: StatementArguments? = nil) throws -> [Row] {
        let start = Date.timeIntervalSinceReferenceDate
        defer {
            self.logSlowQuery(db, query, arguments, start)
        }
        return try Row.fetchAll(db, query, arguments: arguments, adapter: nil)
    }

    private func logSlowQuery(_ db: Database, _ query: String, _ arguments: StatementArguments?, _ start: TimeInterval) {
        let elapsed = Date.timeIntervalSinceReferenceDate - start

        if _isDebugAssertConfiguration() && elapsed >= 0.01 {
            Log.info("slow query: \(elapsed)s for \(query) - arguments: \(String(describing: arguments))" )
            self.queryPlan(db, query, arguments)
        }
    }

    private func queryPlan(_ db: Database, _ query: String, _ arguments: StatementArguments?) {
        do {
            for explain in try Row.fetchAll(db, "EXPLAIN QUERY PLAN " + query, arguments: arguments) {
                Log.debug("EXPLAIN: \(explain)")
            }
        } catch {
            Log.error("query explain error \(error) for \(query)")
        }
    }
}
