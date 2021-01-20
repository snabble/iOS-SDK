//
//  NSLayoutConstraint+Priority.swift
//  Snabble
//
//  Created by Andreas Osberghaus on 20.01.21.
//

import Foundation
import UIKit

extension NSLayoutConstraint {
    /// Returns the constraint sender with the passed priority.
    ///
    /// - Parameter priority: The priority to be set.
    /// - Returns: The sent constraint adjusted with the new priority.
    func usingPriority(_ priority: UILayoutPriority) -> Self {
        self.priority = priority
        return self
    }
}
