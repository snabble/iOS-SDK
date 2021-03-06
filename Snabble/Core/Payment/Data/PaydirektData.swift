//
//  PaydirektData.swift
//
//  Copyright © 2021 snabble. All rights reserved.
//

import Foundation

struct PaydirektData: Codable, EncryptedPaymentData, Equatable {
    // encrypted JSON string
    let encryptedPaymentData: String
    // serial # of the certificate used to encrypt
    let serial: String

    // name of this payment method for display in table
    let displayName: String

    let isExpired = false

    let originType = AcceptedOriginType.paydirektCustomerAuthorization

    let deviceId: String
    let deviceName: String
    let deviceFingerprint: String
    let deviceIpAddress: String

    enum CodingKeys: String, CodingKey {
        case encryptedPaymentData, serial, displayName, deviceId, deviceName
        case deviceFingerprint, deviceIpAddress
    }

    private struct PaydirektOrigin: PaymentRequestOrigin {
        let clientID: String
        let customerAuthorizationURI: String
    }

    init?(_ gatewayCert: Data?, _ authorizationURI: String, _ auth: PaydirektAuthorization) {
        let requestOrigin = PaydirektOrigin(clientID: SnabbleAPI.clientId, customerAuthorizationURI: authorizationURI)

        guard
            let encrypter = PaymentDataEncrypter(gatewayCert),
            let (cipherText, serial) = encrypter.encrypt(requestOrigin)
        else {
            return nil
        }

        self.encryptedPaymentData = cipherText
        self.serial = serial

        self.displayName = "paydirekt"

        self.deviceId = auth.id
        self.deviceName = auth.name
        self.deviceFingerprint = auth.fingerprint
        self.deviceIpAddress = auth.ipAddress
    }

    var additionalData: [String: String] {
        return [
            "deviceID": self.deviceId,
            "deviceName": self.deviceName,
            "deviceFingerprint": self.deviceFingerprint,
            "deviceIPAddress": self.deviceIpAddress
        ]
    }
}
