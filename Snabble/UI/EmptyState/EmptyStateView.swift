//
//  EmptyStateView.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import UIKit

class EmptyStateView: NibView {
    @IBOutlet weak var textLabel: UILabel!
    @IBOutlet weak var button: UIButton!

    typealias Handler = () -> ()
    private let tapHandler: Handler
    
    init(_ tapHandler: @escaping Handler) {
        self.tapHandler = tapHandler
        super.init(frame: CGRect.zero)

        self.backgroundColor = SnabbleUI.appearance.primaryBackgroundColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @IBAction private func buttonTapped(_ sender: UIButton) {
        self.tapHandler()
    }

    func addTo(_ superview: UIView) {
        superview.addSubview(self)

        self.centerXAnchor.constraint(equalTo: superview.centerXAnchor).isActive = true
        self.centerYAnchor.constraint(equalTo: superview.centerYAnchor).isActive = true
        self.leftAnchor.constraint(equalTo: superview.leftAnchor, constant: 16).isActive = true
        self.rightAnchor.constraint(equalTo: superview.rightAnchor, constant: -16).isActive = true
    }

    override var nibName: String {
        return "EmptyStateView"
    }
}

final class ShoppingCartEmptyStateView: EmptyStateView {
    override init(_ tapHandler: @escaping Handler) {
        super.init(tapHandler)

        self.textLabel.text = "Snabble.Shoppingcart.emptyState.description".localized()
        self.button.setTitle("Snabble.Shoppingcart.emptyState.buttonTitle".localized(), for: .normal)
        self.button.setTitleColor(SnabbleUI.appearance.primaryColor, for: .normal)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BarcodeEntryEmptyStateView: EmptyStateView {
    override init(_ tapHandler: @escaping Handler) {
        super.init(tapHandler)

        self.textLabel.text = "Snabble.Scanner.enterBarcode".localized()

        self.button.setTitle("", for: .normal)
        self.button.setTitleColor(SnabbleUI.appearance.primaryColor, for: .normal)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
