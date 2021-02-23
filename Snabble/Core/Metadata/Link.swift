//
//  Link.swift
//
//  Copyright © 2021 snabble. All rights reserved.
//

/// Link
public struct Link: Codable {
    public let href: String

    /// empty instance, used for the default init of `MetadataLinks`
    static let empty = Link(href: "")
}
