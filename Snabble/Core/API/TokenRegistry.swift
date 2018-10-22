//
//  TokenRegistry.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import Foundation
import OneTimePassword
import Base32

// backend response
struct TokenResponse: Decodable {
    let id: String
    let token: String
    let issuedAt: Int64
    let expiresAt: Int64
}

// stored in our token registry
struct TokenData {
    let jwt: String
    let expires: Date
    let refresh: Date
    let project: Project

    init(_ response: TokenResponse, _ project: Project) {
        self.jwt = response.token
        let expires = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
        let refreshIn = (expires.timeIntervalSinceReferenceDate - Date.timeIntervalSinceReferenceDate) / 2
        self.expires = expires
        self.refresh = Date(timeIntervalSinceNow: refreshIn)
        self.project = project
    }
}

class TokenRegistry {

    private var appId = ""
    private var secret = ""

    private var registry = [String: TokenData]()
    private var refreshTimer: Timer?

    init(_ appId: String, _ secret: String) {
        self.appId = appId
        self.secret = secret

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appEnteredForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(appEnteredBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func getToken(for project: Project, completion: @escaping (String?)->() ) {
        if let jwt = self.token(for: project) {
            return completion(jwt)
        }

        // no token in our registry, go fetch it
        self.retrieveToken(for: project) { tokenData in
            if let tokenData = tokenData {
                self.registry[project.id] = tokenData
                self.startRefreshTimer()
                completion(tokenData.jwt)
            } else {
                completion(nil)
            }
        }
    }

    // raw, synchronous token access. externally only used by AppEvent.post() to avoid endless loops
    func token(for project: Project) -> String? {
        if let token = self.registry[project.id] {
            // we already have a token. return it if it's still valid
            let now = Date()
            if token.expires > now {
                return token.jwt
            }
        }
        return nil
    }

    // only for unit testing
    func storeToken(_ projectId: String, _ jwt: String) {
        let now = Int64(Date().timeIntervalSince1970)
        let tokenResponse = TokenResponse(id: projectId, token: jwt, issuedAt: now , expiresAt: now + 3600)
        let tokenData = TokenData(tokenResponse, Project.none)

        self.registry[projectId] = tokenData
    }

    @objc private func appEnteredForeground(_ notification: Notification) {
        // print("app going to fg, start refresh")
        self.startRefreshTimer()
    }

    @objc private func appEnteredBackground(_ notification: Notification) {
        // print("app going to bg, stop refresh")
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
    }

    private func startRefreshTimer() {
        guard let earliest = self.registry.values.min(by: { $0.refresh < $1.refresh }) else {
            return
        }

        let now = Date()
        let refreshIn = earliest.refresh.timeIntervalSinceReferenceDate - now.timeIntervalSinceReferenceDate
        // print("run refresh in \(refreshIn)s")
        self.refreshTimer?.invalidate()
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshIn, repeats: false) { timer in
            self.refreshTokens()
        }
    }

    private func refreshTokens() {
        let now = Date.timeIntervalSinceReferenceDate - 5

        let group = DispatchGroup()
        for tokenData in self.registry.values {
            if tokenData.refresh.timeIntervalSinceReferenceDate > now {
                group.enter()
                let project = tokenData.project
                self.retrieveToken(for: project) { tokenData in
                    if let tokenData = tokenData {
                        self.registry[project.id] = tokenData
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: DispatchQueue.main) {
            self.startRefreshTimer()
        }
    }

    private func retrieveToken(for project: Project, _ date: Date? = nil, completion: @escaping (TokenData?) -> () ) {
        let parameters = [ "role": "retailerApp" ]

        let url = project.links.tokens.href
        project.request(.get, url, jwtRequired: false, parameters: parameters, timeout: 2) { request in
            guard
                var request = request,
                let password = self.generatePassword(date),
                let data = "\(self.appId):\(password)".data(using: .utf8)
            else {
                return completion(nil)
            }

            let base64 = data.base64EncodedString()
            request.addValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            request.cachePolicy = .reloadIgnoringCacheData

            project.perform(request) { (token: TokenResponse?, error, httpResponse) in
                if let token = token {
                    completion(TokenData(token, project))
                } else {
                    if let response = httpResponse, response.statusCode == 403, date == nil {
                        self.retryWithServerDate(project, response, completion: completion)
                        return
                    }
                    completion(nil)
                }
            }
        }
    }

    private func retryWithServerDate(_ project: Project, _ response: HTTPURLResponse, completion: @escaping (TokenData?) -> () ) {
        // not authorized. try again with the content of the the server's "Date" header
        if let serverDate = response.allHeaderFields["Date"] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
            formatter.locale = Locale(identifier: "en_US_Posix")
            if let date = formatter.date(from: serverDate) {
                self.retrieveToken(for: project, date, completion: completion)
            }
        } else {
            completion(nil)
        }
    }

    private func generatePassword(_ date: Date? = nil) -> String? {
        guard
            let secretData = MF_Base32Codec.data(fromBase32String: self.secret),
            let generator = Generator(factor: .timer(period: 30), secret: secretData, algorithm: .sha256, digits: 8)
        else {
            return nil
        }

        let token = Token(name: "", issuer: "", generator: generator)
        do {
            return try token.generator.password(at: date ?? Date())
        }
        catch {
            return nil
        }
    }
    
}
