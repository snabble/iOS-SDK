//
//  Utilities.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

// MARK: - string-based enums

/// for RawRepresentable enums, define a `unknownCase` fallback and a non-failable initializer
protocol UnknownCaseRepresentable: RawRepresentable, CaseIterable where RawValue: Equatable {
    static var unknownCase: Self { get }
}

extension UnknownCaseRepresentable {
    public init(rawValue: RawValue) {
        let value = Self.allCases.first(where: { $0.rawValue == rawValue })
        self = value ?? Self.unknownCase
    }
}

// MARK: - Logging
enum Log {
    static func info(_ str: String) {
        NSLog("SnabbleSDK INFO: %@", str)
    }

    static func debug(_ str: String) {
        NSLog("SnabbleSDK DEBUG: %@", str)
    }

    static func warn(_ str: String) {
        NSLog("SnabbleSDK WARN: %@", str)
    }

    static func error(_ str: String) {
        NSLog("SnabbleSDK ERROR: %@", str)
    }
}
