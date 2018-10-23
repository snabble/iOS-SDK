//
//  ProductDB.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import GRDB
import Zip

/// keys of well-known entries in the metadata table
public struct MetadataKeys {
    public static let revision = "revision"
    public static let schemaVersionMajor = "schemaVersionMajor"
    public static let schemaVersionMinor = "schemaVersionMinor"
}

/// the return type from `productByScannableCode`.
/// - `product` contains the product found
/// - `code` contains the code by which the product was found, which is not necessarily the
///    same as the one that was passed to `productByScannableCode` as a parameter
///    (e.g. when a UPC-A code is scanned as an EAN-13, and the leading "0" filler digits had
///    to be stripped)
public struct LookupResult {
    public let product: Product
    public let code: String?
}

public protocol ProductProvider: class {
    /// initialize a ProductDB instance with the given configuration
    /// - parameter config: a `SnabbleAPIConfig` object
    /// - parameter project: the snabble `Project`
    init(_ config: SnabbleAPIConfig, _ project: Project)

    /// Check if a database file is present for this project
    func hasDatabase() -> Bool

    /// Setup the product database
    ///
    /// The database can be used as soon as this method returns.
    ///
    /// - parameter forceFullDownload: if true, force a full download of the product database
    /// - parameter completion: This is called asynchronously on the main thread after the automatic database update check has finished
    ///   (i.e., only if `update` is true)
    /// - parameter newData: indicates if new data is available
    func setup(update: Bool, forceFullDownload: Bool, completion: @escaping ((Bool) -> ()))

    /// Attempt to update the product database
    ///
    /// - parameter forceFullDownload: if true, force a full download of the product database
    /// - parameter completion: This is called asynchronously on the main thread after the automatic database update check has finished
    ///   (i.e., only if `update` is true)
    /// - parameter newData: indicates if new data is available
    func updateDatabase(forceFullDownload: Bool, completion: @escaping (Bool) -> ())

    /// get a product by its SKU
    func productBySku(_ sku: String, _ shopId: String) -> Product?

    /// get a list of products by their SKUs
    func productsBySku(_ skus: [String], _ shopId: String) -> [Product]

    /// get boosted products
    ///
    /// returns a list of products that have a non-null `boost` value and a valid image URL
    /// the returned list is sorted by descending boost value
    ///
    /// - Parameter limit: number of products to get
    /// - Returns: an array of `Product`
    @available(*, deprecated, message: "this method will be removed in the near future")
    func boostedProducts(limit: Int) -> [Product]

    /// get discounted products
    ///
    /// returns a list of all products that have a discounted price and a valid image URL
    ///
    /// - Returns: an array of `Product`
    func discountedProducts(_ shopId: String) -> [Product]

    @available(*, deprecated, message: "this method will be removed in the near future, use discountedProducts(_:) instead")
    func discountedProducts() -> [Product]

    /// get a product and the code by which it was found by (one of) its scannable codes
    func productByScannableCode(_ code: String, _ shopId: String) -> LookupResult?

    /// get a product by (one of) its weighItemIds
    func productByWeighItemId(_ weighItemId: String, _ shopId: String) -> Product?

    /// get products matching `name`
    ///
    /// The project's `useFTS` flag must be `true` for this to work.
    ///
    /// - Parameter name: the string to search for. The search is case- and diacritic-insensitive
    /// - Returns: an array of matching `Product`s.
    ///   NB: the returned products do not have price information
    func productsByName(_ name: String, filterDeposits: Bool) -> [Product]

    /// searches for products whose scannable codes start with `prefix`
    ///
    /// - Parameters:
    ///   - prefix: the prefix to search for
    ///   - filterDeposits: if true, products with `isDeposit==true` are not returned
    /// - Returns: an array of matching `Product`s
    ///   NB: the returned products do not have price information
    func productsByScannableCodePrefix(_ prefix: String, filterDeposits: Bool) -> [Product]

    // MARK: - asynchronous variants of the product lookup methods

    /// asynchronously get a product by its SKU
    ///
    /// - Parameters:
    ///   - sku: the sku to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    func productBySku(_ sku: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ product: Product?, _ error: Bool) -> () )

    /// asynchronously get a product by (one of) its scannable codes
    ///
    /// - Parameters:
    ///   - code: the code to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    func productByScannableCode(_ code: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ result: LookupResult?, _ error: Bool) -> () )

    /// asynchronously get a product by (one of) it weigh item ids
    ///
    /// - Parameters:
    ///   - weighItemId: the id to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    func productByWeighItemId(_ weighItemId: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ product: Product?, _ error: Bool) -> () )

    var revision: Int64 { get }
    var lastProductUpdate: Date { get }

    var schemaVersionMajor: Int { get }
    var schemaVersionMinor: Int { get }
}

public extension ProductProvider {
    public func setup(completion: @escaping (Bool) -> () ) {
        self.setup(update: true, forceFullDownload: false, completion: completion)
    }

    public func updateDatabase(completion: @escaping (Bool) -> ()) {
        self.updateDatabase(forceFullDownload: false, completion: completion)
    }

    public func productBySku(_ sku: String, _ shopId: String, completion: @escaping (_ product: Product?, _ error: Bool) -> () ) {
        self.productBySku(sku, shopId, forceDownload: false, completion: completion)
    }

    public func productByScannableCode(_ code: String, _ shopId: String, completion: @escaping (_ result: LookupResult?, _ error: Bool) -> () ) {
        self.productByScannableCode(code, shopId, forceDownload: false, completion: completion)
    }

    public func productsByScannableCodePrefix(_ prefix: String, filterDeposits: Bool = true) -> [Product] {
        return self.productsByScannableCodePrefix(prefix, filterDeposits: true)
    }

    public func productByWeighItemId(_ code: String, _ shopId: String, completion: @escaping (_ product: Product?, _ error: Bool) -> () ) {
        self.productByWeighItemId(code, shopId, forceDownload: false, completion: completion)
    }

    public func productsByName(_ name: String) -> [Product] {
        return self.productsByName(name, filterDeposits: true)
    }
}

final class ProductDB: ProductProvider {
    internal let supportedSchemaVersion = 1

    private let dbName = "products.sqlite3"
    private var db: DatabaseQueue?
    private var dbDirectory: URL
    private let config: SnabbleAPIConfig
    let project: Project

    /// revision of the current local product database
    private(set) public var revision: Int64 = 0

    /// major schema version of the current local database
    private(set) public var schemaVersionMajor = 0
    /// minor schema version of the current local database
    private(set) public var schemaVersionMinor = 0

    /// date of last successful product update (i.e, whenever we last got a HTTP status 200 or 304)
    private(set) public var lastProductUpdate = Date()

    /// initialize a ProductDB instance with the given configuration
    /// - parameter config: a `ProductDBConfiguration` object
    public init(_ config: SnabbleAPIConfig, _ project: Project) {
        self.config = config
        self.project = project

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dbDirectory = appSupportDir.appendingPathComponent(project.id, isDirectory: true)
    }

    func dbPathname(temp: Bool = false) -> String {
        let prefix = temp ? "tmp_" : ""
        let dbDir = self.dbDirectory.appendingPathComponent(prefix + self.dbName)
        return dbDir.path
    }

    func hasDatabase() -> Bool {
        return FileManager.default.fileExists(atPath: self.dbPathname())
    }

    /// Setup the product database
    /// - Parameters:
    ///   - forceFullDownload: if true, force a full download of the product database
    ///   - update: if true, attempt to update the database to the latest revision
    ///   - completion: This is called asynchronously on the main thread after the automatic database update check has finished
    ///     (i.e., only if `update` is true)
    ///   - newData: indicates if the database was updated
    public func setup(update: Bool = true, forceFullDownload: Bool = false, completion: @escaping (_ newData: Bool) -> () ) {
        self.db = self.openDb()

        if let seedRevision = self.config.seedRevision, seedRevision > self.revision {
            self.db = nil
            self.unzipSeed()
            self.db = self.openDb()
        }

        if update {
            self.updateDatabase(forceFullDownload: forceFullDownload, completion: completion)
        }
    }

    /// Attempt to update the product database
    /// - Parameters:
    ///   - forceFullDownload: if true, force a full download of the product database
    ///   - completion: This is called asynchronously on the main thread, after the update check has finished.
    ///   - newData: indicates if new data is available
    public func updateDatabase(forceFullDownload: Bool, completion: @escaping (_ newData: Bool)->() ) {
        let schemaVersion = "\(self.schemaVersionMajor).\(self.schemaVersionMinor)"
        let revision = (forceFullDownload || !self.hasDatabase()) ? 0 : self.revision
        self.getAppDb(currentRevision: revision, schemaVersion: schemaVersion) { dbResponse in
            self.lastProductUpdate = Date()

            DispatchQueue.global(qos: .userInitiated).async {
                let performSwitch: Bool
                let newData: Bool
                switch dbResponse {
                case .diff(let statements):
                    NSLog("db update: got diff")
                    performSwitch = self.copyAndUpdateDatabase(statements)
                    newData = true
                case .full(let data, let revision):
                    NSLog("db update: got full db, rev=\(revision)")
                    performSwitch = self.writeFullDatabase(data, revision)
                    newData = true
                case .noUpdate:
                    NSLog("db update: no new data")
                    performSwitch = false
                    newData = false
                case .httpError, .dataError:
                    NSLog("db update: http error or no data")
                    performSwitch = false
                    newData = false
                }

                if self.config.useFTS && newData {
                    self.createFulltextIndex(self.dbPathname(temp: true))
                }

                if performSwitch {
                    self.switchDatabases()
                } else {
                    let tempDbPath = self.dbPathname(temp: true)
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: tempDbPath) {
                        try? fileManager.removeItem(atPath: tempDbPath)
                    }
                }

                DispatchQueue.main.async {
                    completion(newData)
                }
            }
        }
    }

    private func createFulltextIndex(_ path: String) {
        NSLog("creating FTS index...")
        do {
            let db = try DatabaseQueue(path: path)
            try self.createFullTextIndex(db)
        } catch {
            self.logError("create FTS failed: error \(error)")
        }
    }

    private func openDb() -> DatabaseQueue? {
        let fileManager = FileManager.default

        do {
            // ensure database directory exists
            if !fileManager.fileExists(atPath: self.dbDirectory.path) {
                try fileManager.createDirectory(at: self.dbDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            let dbFile = self.dbPathname()

            if !fileManager.fileExists(atPath: dbFile) {
                NSLog("no sqlite file found at \(dbFile)")
                return nil
            }

            NSLog("using sqlite db: \(dbFile)")

            // remove comments to simulate first app installation
//            if fileManager.fileExists(atPath: dbFile) {
//                try fileManager.removeItem(atPath: dbFile)
//            }

            // copy our seed database to the app support directory if the file doesn't exist
            if !fileManager.fileExists(atPath: dbFile) {
                self.unzipSeed()
            }

            var config = Configuration()
            config.readonly = true
            let db = try DatabaseQueue(path: dbFile, configuration: config)
            self.readMetadata(db)
            return db
        } catch let error {
            self.logError("openDb: db setup error \(error)")
            return nil
        }
    }

    private func unzipSeed() {
        if let seedPath = self.config.seedDatabase {
            NSLog("unzipping seed database")
            do {
                let seedUrl = URL(fileURLWithPath: seedPath)
                try Zip.unzipFile(seedUrl, destination: self.dbDirectory, overwrite: true, password: nil)
            } catch let error {
                self.logError("error while unzipping seed: \(error)")
            }

            if self.config.useFTS {
                self.createFulltextIndex(self.dbPathname())
            }
        }
    }

    /// create a new temporary database file from `data`
    ///
    /// - Parameters:
    ///   - data: the bytes to write
    ///   - revision: the revision of this new database
    /// - Returns: true if the database was written successfully and passes internal integrity checks,
    ///         false otherwise
    private func writeFullDatabase(_ data: Data, _ revision: Int) -> Bool {
        let tempDbPath = self.dbPathname(temp: true)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: tempDbPath) {
                try fileManager.removeItem(atPath: tempDbPath)
            }
            let tmpUrl = URL(fileURLWithPath: tempDbPath)
            try data.write(to: tmpUrl, options: .atomic)

            // open the db and check its integrity
            let tempDb = try DatabaseQueue(path: tempDbPath)
            let ok: Bool = try tempDb.inDatabase { db in
                if let result = try String.fetchOne(db, "pragma integrity_check") {
                    return result.lowercased() == "ok"
                } else {
                    return false
                }
            }

            if ok {
                let result = try tempDb.inDatabase { db in
                    return try String.fetchAll(db, """
                        select value from metadata where key='\(MetadataKeys.schemaVersionMajor)'
                        union
                        select value from metadata where key='\(MetadataKeys.schemaVersionMinor)'
                        """)
                }
                guard result.count == 2 else {
                    return false
                }

                let majorVersion = Int(result[0]) ?? 0
                let minorVersion = Int(result[1]) ?? 0

                if majorVersion != self.supportedSchemaVersion {
                    return false
                }

                let shouldSwitch = revision > self.revision || minorVersion > self.schemaVersionMinor
                if shouldSwitch {
                    NSLog("new db: revision=\(revision), schema=\(majorVersion).\(minorVersion)")
                }
                return shouldSwitch
            }
        } catch let error {
            self.logError("writeFullDatabase: db update error \(error)")
        }

        if fileManager.fileExists(atPath: tempDbPath) {
            try? fileManager.removeItem(atPath: tempDbPath)
        }
        return false
    }

    private func copyAndUpdateDatabase(_ statements: String) -> Bool {
        let tempDbPath = self.dbPathname(temp: true)
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: tempDbPath) {
                try fileManager.removeItem(atPath: tempDbPath)
            }
            try fileManager.copyItem(atPath: self.dbPathname(), toPath: tempDbPath)

            let tempDb = try DatabaseQueue(path: tempDbPath)

            try tempDb.inTransaction { db in
                try db.execute(statements)
                return .commit
            }

            try tempDb.inDatabase { db in
                try db.execute("vacuum")
            }
            return true
        } catch let error {
            self.logError("copyAndUpdateDatabase: db update error \(error)")

            try? fileManager.removeItem(atPath: tempDbPath)
            if let dbError = error as? DatabaseError, dbError.resultCode == .SQLITE_CORRUPT {
                // updating or vacuuming the copy reported a malformed database file, so we have to assume that the original was
                // corrupted to begin with. remove the file, and let the next db update start from scratch
                try? fileManager.removeItem(atPath: self.dbPathname())
            }
            return false
        }
    }

    private func switchDatabases() {
        do {
            let fileManager = FileManager.default
            let dbFile = self.dbPathname()
            let oldFile = dbFile + ".old"
            let tmpFile = self.dbPathname(temp: true)
            try synchronized(self) {
                self.db = nil
                if fileManager.fileExists(atPath: oldFile) {
                    try fileManager.removeItem(atPath: oldFile)
                }
                if fileManager.fileExists(atPath: dbFile) {
                    try fileManager.moveItem(atPath: dbFile, toPath: oldFile)
                }
                try fileManager.moveItem(atPath: tmpFile, toPath: dbFile)
                self.db = self.openDb()
            }
            if fileManager.fileExists(atPath: oldFile) {
                try fileManager.removeItem(atPath: oldFile)
            }
        } catch let error {
            self.logError("switchDatabases: db switch error \(error)")
        }
    }

    private func readMetadata(_ db: DatabaseQueue) {
        let metadata = self.metadata(db)

        for (key, value) in metadata {
            switch key {
            case MetadataKeys.revision:
                self.revision = Int64(value) ?? 0
            case MetadataKeys.schemaVersionMajor:
                self.schemaVersionMajor = Int(value) ?? 0
            case MetadataKeys.schemaVersionMinor:
                self.schemaVersionMinor = Int(value) ?? 0
            default:
                break
            }
        }
    }

}

// MARK: - product access methods
extension ProductDB {

    /// get a product by its SKU
    ///
    /// - Parameter sku: the SKU of the product to get
    /// - Returns: a `Product` if found; nil otherwise
    public func productBySku(_ sku: String, _ shopId: String) -> Product? {
        guard let db = self.db else {
            return nil
        }

        return self.productBySku(db, sku, shopId)
    }

    /// get a list of products by their SKUs
    ///
    /// the ordering of the returned products is unspecified
    ///
    /// - Parameter skus: SKUs of the products to get
    /// - Returns: an array of `Product`
    public func productsBySku(_ skus: [String], _ shopId: String) -> [Product] {
        guard let db = self.db, skus.count > 0 else {
            return []
        }

        return self.productsBySku(db, skus, shopId)
    }

    /// get boosted products
    ///
    /// returns a list of products that have a non-null `boost` value and a valid image URL
    /// the returned list is sorted by descending boost value
    ///
    /// - Parameter limit: number of products to get
    /// - Returns: an array of `Product`
    @available(*, deprecated)
    public func boostedProducts(limit: Int) -> [Product] {
        guard let db = self.db else {
            return []
        }

        return self.boostedProducts(db, limit: limit)
    }

    @available(*, deprecated)
    public func discountedProducts() -> [Product] {
        return []
    }

    /// get discounted products
    ///
    /// returns a list of all products that have a discounted price and a valid image URL
    ///
    /// - Returns: an array of `Product`
    public func discountedProducts(_ shopId: String) -> [Product] {
        guard let db = self.db else {
            return []
        }

        return self.discountedProducts(db, shopId)
    }

    /// get a product by its scannable code
    public func productByScannableCode(_ code: String, _ shopId: String) -> LookupResult? {
        guard let db = self.db else {
            return nil
        }

        return self.productByScannableCode(db, code, shopId)
    }

    /// get a product by its weighItemId
    public func productByWeighItemId(_ weighItemId: String, _ shopId: String) -> Product? {
        guard let db = self.db else {
            return nil
        }

        return self.productByWeighItemId(db, weighItemId, shopId)
    }

    /// get products matching `name`
    ///
    /// The project's `useFTS` flag must be `true` for this to work.
    ///
    /// - Parameters:
    ///   - name: the string to search for. The search is case- and diacritic-insensitive
    ///   - filterDeposits: if true, products with `isDeposit==true` are not returned
    /// - Returns: an array of matching Products
    public func productsByName(_ name: String, filterDeposits: Bool = true) -> [Product] {
        guard let db = self.db else {
            return []
        }

        if !self.config.useFTS {
            NSLog("WARNING: productsByName called, but useFTS not set")
        }

        return self.productsByName(db, name, filterDeposits)
    }

    ///
    /// searches for products whose scannable code starts with `prefix`
    ///
    /// - Parameters:
    ///   - prefix: the prefix to search for
    ///   - filterDeposits: if true, products with `isDeposit==true` are not returned
    /// - Returns: an array of matching Products
    public func productsByScannableCodePrefix(_ prefix: String, filterDeposits: Bool) -> [Product] {
        guard let db = self.db else {
            return []
        }

        return self.productsByScannableCodePrefix(db, prefix, filterDeposits)
    }

    // MARK: - asynchronous requests

    /// asynchronously get a product by its SKU
    ///
    /// invokes the completion handler on the main thread with the result of the lookup
    ///
    /// - Parameters:
    ///   - sku: the SKU to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    public func productBySku(_ sku: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ product: Product?, _ error: Bool) -> ()) {
        if !forceDownload, let product = self.productBySku(sku, shopId) {
            DispatchQueue.main.async {
                completion(product, false)
            }
            return
        }

        self.getSingleProduct(self.project.links.productBySku.href, "{sku}", sku, shopId, completion: completion)
    }

    /// asynchronously get a product by (one of) it scannable codes
    ///
    /// invokes the completion handler on the main thread with the result of the lookup
    ///
    /// - Parameters:
    ///   - code: the code to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    public func productByScannableCode(_ code: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ result: LookupResult?, _ error: Bool) -> ()) {
        if !forceDownload, let result = self.productByScannableCode(code, shopId) {
            DispatchQueue.main.async {
                completion(result, false)
            }
            return
        }

        self.getSingleProduct(self.project.links.productByCode.href, "{code}", code, shopId, completion: completion)
    }

    /// asynchronously get a product by (one of) it weigh item ids
    ///
    /// invokes the completion handler on the main thread with the result of the lookup
    ///
    /// - Parameters:
    ///   - weighItemId: the id to look for
    ///   - forceDownload: if true, skip the lookup in the local DB
    ///   - product: the product found, or nil.
    ///   - error: whether an error occurred during the lookup.
    public func productByWeighItemId(_ weighItemId: String, _ shopId: String, forceDownload: Bool, completion: @escaping (_ product: Product?, _ error: Bool) -> ()) {
        if !forceDownload, let product = self.productByWeighItemId(weighItemId, shopId) {
            DispatchQueue.main.async {
                completion(product, false)
            }
            return
        }

        self.getSingleProduct(self.project.links.productByWeighItemId.href, "{id}", weighItemId, shopId, completion: completion)
    }

    func logError(_ msg: String) {
        self.project.logError(msg)
    }
}
