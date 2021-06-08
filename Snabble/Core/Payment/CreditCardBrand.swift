//
//  CreditCardBrand.swift
//
//  Copyright © 2021 snabble. All rights reserved.
//

import Foundation

// unfortunately we have to maintain a bunch of different mappings to strings
public enum CreditCardBrand: String, Codable {
    // 1st mapping: from the reponse of the IPG card entry form; also used for datatrans
    case visa
    case mastercard
    case amex

    // 2nd mapping: to the `cardType` property of the encrypted payment data
    var cardType: String {
        switch self {
        case .visa: return "creditCardVisa"
        case .mastercard: return "creditCardMastercard"
        case .amex: return "creditCardAmericanExpress"
        }
    }

    // 3rd mapping: to the `paymentMethod` form field of the IPG card entry form
    var paymentMethod: String {
        switch self {
        case .visa: return "V"
        case .mastercard: return "M"
        case .amex: return "A"
        }
    }

    // 4th mapping: to a user-facing string
    var displayName: String {
        switch self {
        case .visa: return "VISA"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        }
    }
}