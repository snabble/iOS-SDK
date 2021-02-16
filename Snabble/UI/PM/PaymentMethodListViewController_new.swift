//
//  PaymentMethodListViewController.swift
//
//  Copyright © 2021 snabble. All rights reserved.
//

// NB class and file name will change once we can delete the old existing class

import UIKit
import SDCAlertView

public final class PaymentMethodListViewControllerNew: UIViewController {
    private var tableView = UITableView(frame: .zero, style: .grouped)

    private var details = [[PaymentMethodDetail]]()
    private let showFromCart: Bool
    private weak var analyticsDelegate: AnalyticsDelegate?

    private let projectId: Identifier<Project>?
    private let method: RawPaymentMethod?
    private let availableMethods: [RawPaymentMethod]

    public init(method: RawPaymentMethod, for projectId: Identifier<Project>?, showFromCart: Bool, _ analyticsDelegate: AnalyticsDelegate?) {
        self.showFromCart = showFromCart
        self.analyticsDelegate = analyticsDelegate
        self.projectId = projectId
        self.method = method
        self.availableMethods = [ method ]

        super.init(nibName: nil, bundle: nil)
    }

    public init(for projectId: Identifier<Project>, showFromCart: Bool, _ analyticsDelegate: AnalyticsDelegate?) {
        self.showFromCart = showFromCart
        self.analyticsDelegate = analyticsDelegate
        self.projectId = projectId
        self.method = nil
        self.availableMethods = SnabbleAPI.projects
            .filter { $0.id == projectId }
            .flatMap { $0.paymentMethods }
            .filter { $0.isProjectSpecific }

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Snabble.PaymentMethods.title".localized()

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addMethod))
        self.navigationItem.rightBarButtonItem = addButton

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.rowHeight = 44
        tableView.register(PaymentMethodListCell.self, forCellReuseIdentifier: "cell")
        self.view.addSubview(tableView)

        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: tableView.topAnchor),
            self.view.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            self.view.leftAnchor.constraint(equalTo: tableView.leftAnchor),
            self.view.rightAnchor.constraint(equalTo: tableView.rightAnchor)
        ])
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.details = []

        if let projectId = self.projectId {
            let details = PaymentMethodDetails.read().filter { detail in
                switch detail.methodData {
                case .creditcard(let creditcardData):
                    return creditcardData.projectId == projectId
                default:
                    return false
                }
            }

            Dictionary(grouping: details, by: { $0.rawMethod })
                .values
                .sorted { $0[0].displayName < $1[0].displayName }
                .forEach {
                    self.details.append($0)
                }
        } else if let method = self.method {
            let details = PaymentMethodDetails.read()
                .filter { $0.rawMethod == method }
                .sorted { $0.displayName < $1.displayName }

            self.details = [ details ]
        }

        self.tableView.reloadData()
    }

    @objc private func addMethod() {
        let methods = self.availableMethods

        if methods.count == 1 {
            showEditController(for: methods[0])
            return
        }

        let sheet = AlertController(title: "Snabble.PaymentMethods.choose".localized(), message: nil, preferredStyle: .actionSheet)
        methods.forEach { method in
            let title = NSAttributedString(string: method.displayName, attributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: 17)
            ])
            let action = AlertAction(attributedTitle: title, style: .normal) { [self] _ in
                showEditController(for: method)
            }
            action.imageView.image = method.icon
            sheet.addAction(action)
        }

        let cancelTitle = NSAttributedString(string: "Snabble.Cancel".localized(), attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: UIColor.label
        ])
        sheet.addAction(AlertAction(attributedTitle: cancelTitle, style: .preferred, handler: nil))

        self.present(sheet, animated: true)
    }

    private func showEditController(for method: RawPaymentMethod) {
        if let controller = method.editViewController(with: projectId, showFromCart: showFromCart, analyticsDelegate) {
            #warning("RN navigation")
            navigationController?.pushViewController(controller, animated: true)
        }
    }
}

extension PaymentMethodListViewControllerNew: UITableViewDelegate, UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return details.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return details[section].count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // swiftlint:disable:next force_cast
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! PaymentMethodListCell

        cell.method = details[indexPath.section][indexPath.row]

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let detail = details[indexPath.section][indexPath.row]

        var editVC: UIViewController?
        switch detail.methodData {
        case .sepa:
            editVC = SepaEditViewController(detail, false, self.analyticsDelegate)
        case .creditcard:
            editVC = CreditCardEditViewController(detail, false, self.analyticsDelegate)
        case .paydirektAuthorization:
            editVC = PaydirektEditViewController(detail, false, self.analyticsDelegate)
        case .tegutEmployeeCard:
            editVC = nil
        }

        if let controller = editVC {
            #warning("RN navigation")
            self.navigationController?.pushViewController(controller, animated: true)
        }
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else {
            return
        }

        let detail = details[indexPath.section][indexPath.row]
        PaymentMethodDetails.remove(detail)
        details[indexPath.section].remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return details[section].first?.rawMethod.displayName
    }
}

private final class PaymentMethodListCell: UITableViewCell {
    var method: PaymentMethodDetail? {
        didSet {
            self.nameLabel.text = method?.displayName
            self.icon.image = method?.icon
        }
    }

    private var nameLabel = UILabel()
    private var icon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        accessoryType = .disclosureIndicator

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        contentView.addSubview(icon)

        NSLayoutConstraint.activate([
            icon.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),

            nameLabel.leftAnchor.constraint(equalTo: icon.rightAnchor, constant: 16),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
