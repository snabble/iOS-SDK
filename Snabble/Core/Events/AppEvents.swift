//
//  AppEvents.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import Foundation

enum EventType: String, Encodable {
    case sessionStart
    case sessionEnd
    case cart
    case error
    case log
    case analytics
    case productNotFound
}

private struct Session: Encodable {
    let session: String
}

private struct Message: Encodable {
    let message: String
    let session: String?
}

private struct Analytics: Encodable {
    let key: String
    let value: String
    let comment: String
}

private struct ProductNotFound: Encodable {
    let scannedCode: String
    let matched: [String: String]
}

private enum Payload: Encodable {
    case session(Session)
    case error(Message)
    case cart(Cart)
    case log(Message)
    case analytics(Analytics)
    case productNotFound(ProductNotFound)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .session(let session): try container.encode(session)
        case .error(let msg): try container.encode(msg)
        case .log(let msg): try container.encode(msg)
        case .cart(let cart): try container.encode(cart)
        case .analytics(let analytics): try container.encode(analytics)
        case .productNotFound(let notFound): try container.encode(notFound)
        }
    }
}

struct AppEvent: Encodable {
    private let type: EventType
    private let appId: String
    private let payload: Payload
    private let projectId: String
    private let timestamp: String

    private let shopId: String?
    private let id: String?
    private let agent: String?

    private let project: Project

    enum CodingKeys: String, CodingKey {
        case type, appId, payload, timestamp
        case projectId = "project"
        case shopId, id, agent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.appId, forKey: .appId)
        try container.encode(self.payload, forKey: .payload)
        try container.encode(self.projectId, forKey: .projectId)
        try container.encode(self.timestamp, forKey: .timestamp)
        try container.encode(self.shopId, forKey: .shopId)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.agent, forKey: .agent)
    }

    private init(type: EventType, payload: Payload, project: Project,
                 shopId: String? = nil, id: String? = nil, agent: String? = nil) {
        self.type = type
        self.appId = SnabbleAPI.clientId
        self.payload = payload
        self.shopId = shopId
        self.project = project
        self.projectId = project.id
        self.id = id
        self.agent = agent
        self.timestamp = Snabble.iso8601Formatter.string(from: Date())
    }

    init(_ type: EventType, session: String, project: Project, shopId: String? = nil) {
        assert(type == .sessionStart || type == .sessionEnd, "session events must have a session type")
        let session = Payload.session(Session(session: session))
        self.init(type: type, payload: session, project: project, shopId: shopId)
    }

    init(error: String, project: Project, session: String? = nil, shopId: String? = nil) {
        let error = Payload.error(Message(message: error, session: session))
        self.init(type: .error, payload: error, project: project, shopId: shopId)
    }

    init(log: String, project: Project, session: String? = nil, shopId: String? = nil) {
        let log = Payload.log(Message(message: log, session: session))
        self.init(type: .log, payload: log, project: project, shopId: shopId)
    }

    init(key: String, value: String, comment: String = "", project: Project) {
        let analytics = Payload.analytics(Analytics(key: key, value: value, comment: comment))
        self.init(type: .analytics, payload: analytics, project: project)
    }

    init?(_ shoppingCart: ShoppingCart) {
        let cart = shoppingCart.createCart()
        guard let project = SnabbleAPI.projectFor(shoppingCart.projectId) else {
            return nil
        }

        self.init(type: .cart, payload: Payload.cart(cart), project: project, shopId: shoppingCart.shopId)
    }

    init(scannedCode: String, codes: [(String, String)], project: Project) {
        var dict = [String: String]()
        for (code, template) in codes {
            dict[template] = code
        }

        let notFound = Payload.productNotFound(ProductNotFound(scannedCode: scannedCode, matched: dict))
        self.init(type: .productNotFound, payload: notFound, project: project)
    }
}

extension AppEvent {

    func post() {
        // use URLRequest/URLSession directly to avoid error logging loops when posting the event fails
        guard
            let url = SnabbleAPI.urlFor(self.project.links.appEvents.href),
            let token = SnabbleAPI.tokenRegistry.token(for: self.project)
        else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            request.httpBody = try JSONEncoder().encode(self)
            request.addValue(token, forHTTPHeaderField: "Client-Token")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            if let userAgent = Project.userAgent {
                request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
        }
        catch {
            Log.error("\(error)")
        }

        // use a system default session here so we can still log pinning errors
        let task = URLSession.shared.dataTask(with: request) { rawData, response, error in
            if let error = error {
                Log.error("posting event failed: \(error)")
            }
        }
        task.resume()
    }

}

public enum RatingEvent {
    public static func track(_ project: Project, _ value: Int, _ comment: String?) {
        let event = AppEvent(key: "rating", value: "\(value)", comment: comment ?? "", project: project)
        event.post()
    }
}
