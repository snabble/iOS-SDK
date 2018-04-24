//
//  BarcodeEntryViewController.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit
import DZNEmptyDataSet

class BarcodeEntryViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var bottomMargin: NSLayoutConstraint!

    private weak var productProvider: ProductProvider!

    private var completion: ((String)->Void)!

    private var filteredProducts = [Product]()
    private var searchText = ""
    private var keyboardObserver: KeyboardObserver!
    private weak var delegate: AnalyticsDelegate!

    init(_ productProvider: ProductProvider, delegate: AnalyticsDelegate, completion: @escaping (String)->() ) {
        super.init(nibName: nil, bundle: Snabble.bundle)

        self.productProvider = productProvider
        self.completion = completion
        self.delegate = delegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.emptyDataSetSource = self
        self.tableView.emptyDataSetDelegate = self
        
        self.tableView.tableFooterView = UIView(frame: CGRect.zero)

        self.searchBar.placeholder = "Snabble.Scanner.enterBarcode".localized()
        
        self.keyboardObserver = KeyboardObserver(handler: self)
        
        let primaryBackgroundColor = SnabbleAppearance.shared.config.primaryBackgroundColor
        self.view.backgroundColor = primaryBackgroundColor
        self.tableView.backgroundColor = .clear
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.searchBar.becomeFirstResponder()

        self.delegate.track(.viewBarcodeEntry)
    }

    // MARK: - search bar
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.filteredProducts = self.productProvider.productsByScannableCodePrefix(searchText, filterDeposits: true)

        self.searchText = searchText
        self.tableView.reloadData()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        let _ = self.navigationController?.popViewController(animated: true)
    }

    // MARK: - table view
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredProducts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "barcodeCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? {
            let c = UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
            c.selectionStyle = .none
            return c
        }()
        
        let product = self.filteredProducts[indexPath.row]
        
        let matchingEan = product.scannableCodes.filter { $0.contains(self.searchText) }.first ?? product.scannableCodes.first!
        
        let str = NSMutableAttributedString(string: matchingEan)
        let boldFont = UIFont.systemFont(ofSize: cell.textLabel?.font.pointSize ?? 0, weight: .medium)
        str.addAttributes([NSAttributedStringKey.font : boldFont], range: NSMakeRange(0, self.searchText.count))
        cell.textLabel?.attributedText = str


        cell.detailTextLabel?.text = product.name
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let product = self.filteredProducts[indexPath.row]

        self.addCode(product.scannableCodes.first!)
    }

    func addCode(_ code: String) {
        // popViewController has no completion handler, so we roll our own
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            self.delegate.track(.barcodeSelected(code))
            self.completion?(code)
        }

        let _ = self.navigationController?.popViewController(animated: false)
        CATransaction.commit()
    }
    
}

// MARK: - empty set
extension BarcodeEntryViewController: DZNEmptyDataSetSource, DZNEmptyDataSetDelegate {

    func description(forEmptyDataSet scrollView: UIScrollView!) -> NSAttributedString! {
        let msg = self.searchText.count > 0 ? "Snabble.Scanner.noMatchesFound" : "Snabble.Scanner.enterBarcode"
        
        return NSAttributedString(string: msg.localized())
    }

    func buttonTitle(forEmptyDataSet scrollView: UIScrollView!, for state: UIControlState) -> NSAttributedString! {
        if self.searchText.count == 0 {
            return nil
        }

        let primaryColor = SnabbleAppearance.shared.config.primaryColor
        let str = NSAttributedString(string: "Snabble.Scanner.addCodeAsIs".localized(), attributes: [NSAttributedStringKey.foregroundColor: primaryColor])
        return str
    }

    func emptyDataSet(_ scrollView: UIScrollView!, didTap button: UIButton!) {
        self.searchBar.resignFirstResponder()
        self.addCode(self.searchText)
    }

}

extension BarcodeEntryViewController: KeyboardHandling {

    func keyboardWillShow(_ info: KeyboardInfo) {
        // compensate for the opaque tab bar
        let tabBarHeight = self.tabBarController?.tabBar.frame.height ?? 0
        let keyboardHeight = info.keyboardHeight - tabBarHeight

        self.bottomMargin.constant = keyboardHeight
    }

    func keyboardWillHide(_ info: KeyboardInfo) {
        // not used
    }

}