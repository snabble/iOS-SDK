//
//  Misc.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//
//  Miscellaneous UI utility methods that don't warrant having their own source file

import UIKit

extension UIView {
    /// add a "rounded button" appearance to this view
    public func makeSnabbleButton() {
        self.layer.cornerRadius = 8
        self.backgroundColor = SnabbleUI.appearance.accentColor
        self.tintColor = SnabbleUI.appearance.accentColor.contrast
    }

    /// add a "bordered button" appearance to this view
    public func makeBorderedButton() {
        self.layer.cornerRadius = 6
        self.backgroundColor = .secondarySystemBackground
        self.layer.borderWidth = 1 / UIScreen.main.scale
        self.layer.borderColor = UIColor.borderColor.cgColor
    }

    /// add a "rounded card" appearance to this view
    public func addCornersAndShadow(backgroundColor: UIColor, cornerRadius: CGFloat) {
        self.layer.shadowColor = UIColor.shadowColor.cgColor
        self.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.layer.shadowOpacity = 0.5
        self.layer.shadowRadius = 2.0

        self.backgroundColor = UIColor.clear

        self.addBorderView(backgroundColor, cornerRadius)
    }

    @discardableResult
    private func addBorderView(_ bgColor: UIColor, _ cornerRadius: CGFloat) -> UIView {
        let borderView = UIView()
        borderView.backgroundColor = bgColor
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.layer.cornerRadius = cornerRadius
        borderView.layer.masksToBounds = true

        self.addSubview(borderView)

        borderView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        borderView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        borderView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        borderView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true

        self.sendSubviewToBack(borderView)

        return borderView
    }
}

public extension UIImage {
    /// use `self` as a mask to produce an image that only uses `color`
    ///
    /// used to generate icons suitable for use in a tabbar, since we can't use
    /// unselectedItemTintColor yet
    func recolored(with color: UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        color.setFill()

        guard let context = UIGraphicsGetCurrentContext() else {
            return self
        }

        context.translateBy(x: 0, y: self.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.setBlendMode(.normal)

        let rect = CGRect(origin: CGPoint.zero, size: self.size)
        context.clip(to: rect, mask: self.cgImage!)
        context.fill(rect)

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage!.withRenderingMode(.alwaysOriginal)
    }

    /// create a grayscale version of `self`
    func grayscale(brightness: Double = 0.0, contrast: Double = 1.0) -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }

        let inputImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIColorControls")
        let params: [String: Any] = [
            kCIInputImageKey: inputImage,
            kCIInputBrightnessKey: brightness,
            kCIInputContrastKey: contrast,
            kCIInputSaturationKey: 0.0
        ]
        filter?.setValuesForKeys(params)

        guard
            let outputImage = filter?.outputImage,
            let filteredImage = CIContext().createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: filteredImage, scale: self.scale, orientation: self.imageOrientation)
    }
}

/// Base class for UIViews that can be used directy in interface builder.
@IBDesignable
open class DesignableView: NibView {}

/// Base class for UIViews that can be instantiated from a NIB
open class NibView: UIView {
    public var view: UIView!

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.nibSetup(self.nibName)
        self.awakeFromNib()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.nibSetup(self.nibName)
        self.awakeFromNib()
    }

    func nibSetup(_ nibName: String) {
        let nib = self.getNib(for: nibName)
        // swiftlint:disable:next force_cast
        self.view = (nib.instantiate(withOwner: self, options: nil)[0] as! UIView)

        // use bounds not frame or it'll be offset
        self.view.frame = self.bounds

        // Add custom subview on top of our view
        self.addSubview(self.view)

        // Make the view stretch with the containing view
        // view.autoresizingMask = [UIViewAutoresizing.flexibleWidth, UIViewAutoresizing.flexibleHeight]
        self.translatesAutoresizingMaskIntoConstraints = false
        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.view.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        self.view.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        self.view.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
    }

    func getNib(for name: String) -> UINib {
        let bundle = Bundle(for: type(of: self))
        if bundle.path(forResource: name, ofType: "nib") != nil {
            return UINib(nibName: name, bundle: bundle)
        } else {
            return UINib(nibName: name, bundle: self.nibBundle)
        }
    }

    // override this if the name of the .xib file is not $CLASSNAME.xib
    open var nibName: String {
        return String(describing: type(of: self))
    }

    open var nibBundle: Bundle {
        return SnabbleBundle.main
    }
}

@IBDesignable
final class InsetLabel: UILabel {
    @IBInspectable var topInset: CGFloat = 0
    @IBInspectable var leftInset: CGFloat = 0
    @IBInspectable var bottomInset: CGFloat = 0
    @IBInspectable var rightInset: CGFloat = 0

    override func drawText(in rect: CGRect) {
        let insets = UIEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + leftInset + rightInset, height: size.height + topInset + bottomInset)
    }
}

// MARK: - l10n and image support

extension String {
    func localized() -> String {
        // check if the app has a project-specific localization for this string
        let projectId = SnabbleUI.project.id.rawValue.replacingOccurrences(of: "-", with: ".")
        let key = projectId + "." + self
        let projectValue = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        if !projectValue.hasPrefix(projectId) {
            return projectValue
        }

        // check if the app has localized this string
        let upper = self.uppercased()
        let appValue = Bundle.main.localizedString(forKey: self, value: upper, table: nil)
        if appValue != upper {
            return appValue
        }

        // check the SDK's localization file
        let sdkValue = SnabbleBundle.main.localizedString(forKey: self, value: upper, table: "SnabbleLocalizable")
        return sdkValue
    }

    public func snabbleLocalized() -> String {
        return self.localized()
    }
}

extension UIImage {
    /// get an image from either the main or our snabble bundle
    static func fromBundle(_ name: String?) -> UIImage? {
        guard let name = name else {
            return nil
        }

        // try the main bundle first
        if let img = UIImage(named: name, in: Bundle.main, compatibleWith: nil) {
            return img
        }

        return UIImage(named: name, in: SnabbleBundle.main, compatibleWith: nil)
    }
}

extension UIApplication {
    class func topViewController(_ base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(presented)
        }
        return base
    }

    class func topNavigationController() -> UINavigationController? {
        return topViewController()?.navigationController
    }
}

extension UINavigationController {
    /// pop to the top-most instance of the given UIViewController, or one where it is a child viewController
    /// If none found, pop one level
    func popToInstanceOf(_ instanceType: UIViewController.Type, animated: Bool) {
        if let target = self.findTarget(of: instanceType) {
            self.popToViewController(target, animated: animated)
        } else {
            self.popViewController(animated: animated)
        }
    }

    private func findTarget(of instanceType: UIViewController.Type) -> UIViewController? {
        if let instance = self.viewControllers.first(where: { type(of: $0) == instanceType }) {
            return instance
        }

        if let parent = self.viewControllers.flatMap({ $0.children }).first(where: { type(of: $0) == instanceType })?.parent {
            return parent
        }

        return nil
    }
}
