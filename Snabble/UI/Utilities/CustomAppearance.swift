//
//  CustomAppearance.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//
//  "Chameleon mode" support

public protocol CustomAppearance {
    var accentColor: UIColor { get }
    var buttonTextColor: UIColor { get }

    var buttonBorderColor: UIColor { get }
    var buttonShadowColor: UIColor { get }

    var titleIcon: UIImage? { get }
}

public extension CustomAppearance {
    var accentColor: UIColor { UIColor(rgbValue: 0x0077bb) }
    var buttonTextColor: UIColor { .white }

    var buttonShadowColor: UIColor { UIColor(rgbaValue: 0x2222223f) }
    var buttonBorderColor: UIColor { UIColor(rgbaValue: 0x00000019) }
    var titleIcon: UIImage? { nil }
}

public protocol CustomizableAppearance: AnyObject {
    func setCustomAppearance(_ appearance: CustomAppearance)
}

extension UIButton: CustomizableAppearance {
    public func setCustomAppearance(_ appearance: CustomAppearance) {
        self.backgroundColor = appearance.accentColor
        self.tintColor = appearance.buttonTextColor
    }
}
