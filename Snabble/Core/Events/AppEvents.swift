//
//  AppEvents.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import Foundation

enum EventType: String, Encodable {
    case sessionStart
    case sessionEnd
    case cart
    case error
}

private struct Session: Encodable {
    let session: String
}

private struct Error: Encodable {
    let message: String
    let session: String?
}

private enum Payload: Encodable {
    case session(Session)
    case error(Error)
    case cart(Cart)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .session(let session): try container.encode(session)
        case .error(let error): try container.encode(error)
        case .cart(let cart): try container.encode(cart)
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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        self.timestamp = fmt.string(from: Date())
    }

    init(_ type: EventType, session: String, project: Project, shopId: String? = nil) {
        assert(type == .sessionStart || type == .sessionEnd, "session events must have a session type")
        let session = Payload.session(Session(session: session))
        self.init(type: type, payload: session, project: project, shopId: shopId)
    }

    init(message: String, project: Project, session: String? = nil, shopId: String? = nil) {
        let error = Payload.error(Error(message: message, session: session))
        self.init(type: .error, payload: error, project: project, shopId: shopId)
    }

    init(_ shoppingCart: ShoppingCart) {
        let cart = shoppingCart.createCart()
        self.init(type: .cart, payload: Payload.cart(cart), project: shoppingCart.config.project, shopId: cart.shopID)
    }

}

extension AppEvent {

    struct Empty: Decodable { }

    func post() {
        project.request(.post, project.links.appEvents.href, body: self, timeout: 0) { request in
            guard let request = request else {
                return
            }

            // NSLog("posting event \(String(describing: self))")
            self.project.perform(request) { (result: Empty?, error) in
                if let error = error {
                    NSLog("error posting event: \(error)")
                }
            }
        }
    }

}
