//
//  OrderList.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

import Foundation

public struct OrderList: Decodable {
    public let orders: [Order]

    public var receipts: [Order] {
        return orders.filter {
            if let href = $0.links.receipt?.href {
                return !href.isEmpty
            }
            return false
        }
    }
}

public struct Order: Codable {
    public let projectId: Identifier<Project>
    public let id: String
    public let date: Date
    public let shopId: String
    public let shopName: String
    public let price: Int
    public let links: OrderLinks

    public struct OrderLinks: Codable {
        public let receipt: Link?
    }

    enum CodingKeys: String, CodingKey {
        case projectId = "project", id, date, shopName, price, links
        case shopId = "shopID"
    }
}

extension OrderList {
    public static func load(_ project: Project, completion: @escaping (Result<OrderList, SnabbleError>) -> Void ) {
        var url: String?
        if let clientOrdersUrl = SnabbleAPI.links.clientOrders?.href {
            url = clientOrdersUrl.replacingOccurrences(of: "{clientID}", with: SnabbleAPI.clientId)
        }

        if let appUserId = SnabbleAPI.appUserId {
            url = SnabbleAPI.links.appUserOrders.href.replacingOccurrences(of: "{appUserID}", with: appUserId.userId)
        }

        guard let ordersUrl = url else {
            return completion(Result.failure(SnabbleError.noRequest))
        }

        project.request(.get, ordersUrl, timeout: 0) { request in
            guard let request = request else {
                return completion(Result.failure(SnabbleError.noRequest))
            }

            project.perform(request) { (result: Result<OrderList, SnabbleError>) in
                completion(result)
            }
        }
    }

    static func clearCache() {
        let fileManager = FileManager.default
        // swiftlint:disable:next force_try
        let cacheDir = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        do {
            let files = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
            for file in files {
                if file.hasPrefix("snabble-order-") && file.hasSuffix(".pdf") {
                    let fullPath = cacheDir.appendingPathComponent(file)
                    try fileManager.removeItem(atPath: fullPath.path)
                    print("deleted \(file)")
                }
            }
        } catch {
            print(error)
        }
    }
}

extension Order {
    public func getReceipt(_ project: Project, completion: @escaping (Result<URL, Error>) -> Void) {
        let fileManager = FileManager.default
        // swiftlint:disable:next force_try
        let cacheDir = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let targetPath = cacheDir.appendingPathComponent("snabble-order-\(self.id).pdf")

        // uncomment to force new downloads on every access
        // try? fileManager.removeItem(at: targetPath)

        if fileManager.fileExists(atPath: targetPath.path) {
            completion(.success(targetPath))
        } else {
            self.download(project, targetPath) { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    private func download(_ project: Project, _ targetPath: URL, completion: @escaping (Result<URL, Error>) -> Void ) {
        guard let link = self.links.receipt?.href else {
            Log.error("error downloading receipt: no receipt link?!?")
            return completion(.failure(SnabbleError.notFound))
        }

        project.request(.get, link, timeout: 10) { request in
            guard let request = request else {
                completion(.failure(SnabbleError.noRequest))
                return
            }

            let session = SnabbleAPI.urlSession()
            let task = session.downloadTask(with: request) { location, _, error in
                if let error = error {
                    Log.error("error downloading receipt: \(String(describing: error))")
                    return completion(.failure(error))
                }

                guard let location = location else {
                    Log.error("error downloading receipt: no location?!?")
                    return completion(.failure(SnabbleError.notFound))
                }

                do {
                    try FileManager.default.moveItem(at: location, to: targetPath)
                    completion(.success(targetPath))
                } catch {
                    Log.error("error saving receipt: \(error)")
                    completion(.failure(SnabbleError.notFound))
                }
            }
            task.resume()
        }
    }
}
