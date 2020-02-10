//
//  MessageDelegate.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

public protocol MessageDelegate: class {
    func showInfoMessage(_ message: String)
    func showWarningMessage(_ message: String)
}
