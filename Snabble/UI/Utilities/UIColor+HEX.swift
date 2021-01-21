//
//  UIColor+HEX.swift
//  Snabble
//
//  Created by Andreas Osberghaus on 21.01.21.
//

import Foundation
import UIKit

extension UIColor {
  convenience init(rgbaValue: UInt32) {
    let obaque = UInt32(0xff)
    let red = CGFloat((rgbaValue >> 24) & obaque) / 255.0
    let green = CGFloat((rgbaValue >> 16) & obaque) / 255.0
    let blue = CGFloat((rgbaValue >> 8) & obaque) / 255.0
    let alpha = CGFloat((rgbaValue) & obaque) / 255.0

    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  convenience init(rgbValue: UInt32) {
    let obaque = UInt32(0xff)
    let red = CGFloat((rgbValue >> 16) & obaque) / 255.0
    let green = CGFloat((rgbValue >> 8) & obaque) / 255.0
    let blue = CGFloat((rgbValue) & obaque) / 255.0

    self.init(red: red, green: green, blue: blue, alpha: 1.0)
  }
}
