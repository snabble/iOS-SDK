//
//  ReceiptCell.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

import UIKit

final class ReceiptCell: UITableViewCell {

    @IBOutlet private weak var storeIcon: UIImageView!
    @IBOutlet private weak var storeName: UILabel!
    @IBOutlet private weak var orderDate: UILabel!
    @IBOutlet private weak var price: UILabel!

    @IBOutlet private weak var iconWidth: NSLayoutConstraint!
    @IBOutlet private weak var iconDistance: NSLayoutConstraint!

    private var projectId = ""

    override func awakeFromNib() {
        super.awakeFromNib()

        self.prepareForReuse()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.storeIcon.image = nil
        self.storeName.text = nil
        self.orderDate.text = nil
        self.price.text = nil

        self.iconWidth.constant = 0
        self.iconDistance.constant = 0

        self.projectId = ""
    }

    func show(_ orderEntry: OrderEntry) {
        switch orderEntry {
        case .done(let order):
            guard let project = SnabbleAPI.projectFor(order.project) else {
                return
            }

            self.accessoryType = .disclosureIndicator
            self.storeName.text = order.shopName

            self.showIcon(order.project)

            let formatter = PriceFormatter(project)
            self.price.text = formatter.format(order.price)

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let date = dateFormatter.string(from: order.date)
            self.orderDate.text = date

        case .pending(let shopName, let projectId):
            self.storeName.text = shopName
            self.showIcon(projectId)
            self.orderDate.text = "Snabble.Receipts.loading".localized()
            let spinner = UIActivityIndicatorView(style: .gray)
            spinner.startAnimating()
            self.accessoryView = spinner
            self.price.text = ""
        }
    }

    private func showIcon(_ projectId: String) {
        self.projectId = projectId

        SnabbleUI.getAsset(.storeIcon, projectId: projectId) { img in
            if let img = img, self.projectId == projectId {
                self.updateImage(img)
            } else {
                let img = UIImage(named: projectId)
                self.updateImage(img)
            }
        }
    }

    private func updateImage(_ img: UIImage?) {
        self.storeIcon.image = img
        if img != nil {
            self.iconWidth.constant = 24
            self.iconDistance.constant = 16
        }
    }
}
