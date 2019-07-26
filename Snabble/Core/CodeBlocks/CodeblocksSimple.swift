//
//  CodeblocksSimple.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//
//  generate a simple QR code

import Foundation

final class CodeblocksSimple {

    private let config: QRCodeConfig

    init(_ config: QRCodeConfig) {
        self.config = config
    }
    
    func generateQrCodes(_ cart: ShoppingCart) -> [String] {
        let (regularCodes, restrictedCodes) = self.codesForQR(cart)
        return self.generateQrCodes(regularCodes, restrictedCodes)
    }

    func generateQrCodes(_ regularCodes: [String], _ restrictedCodes: [String]) -> [String] {
        let codeblocks = self.generateBlocks(regularCodes, restrictedCodes)
        return codeblocks.map { self.qrCodeContent($0) }
    }

    private func qrCodeContent(_ codes: [String]) -> String {
        return self.config.prefix + codes.joined(separator: self.config.separator) + self.config.suffix
    }

    private func codesForQR(_ cart: ShoppingCart) -> ([String],[String]) {
        if self.config.nextCodeWithCheck != nil {
            let regularItems = cart.items.filter { return $0.product.saleRestriction == .none }
            let restrictedItems = cart.items.filter { return $0.product.saleRestriction != .none }

            var regularCodes = [String]()
            if let card = cart.customerCard {
                regularCodes.append(card)
            }
            regularCodes += QRCodeData.codesFor(regularItems)

            let restrictedCodes = QRCodeData.codesFor(restrictedItems)

            return (regularCodes, restrictedCodes)
        } else {
            var codes = [String]()
            if let card = cart.customerCard {
                codes.append(card)
            }
            codes += QRCodeData.codesFor(cart.items)

            return (codes, [])
        }
    }

    func generateBlocks(_ regularCodes: [String], _ restrictedCodes: [String]) -> [[String]] {
        let leaveRoom = self.config.nextCode != nil || self.config.nextCodeWithCheck != nil || self.config.finalCode != nil
        let maxCodes = self.config.maxCodes - (leaveRoom ? 1 : 0)

        var regularBlocks = self.blocksFor(regularCodes, maxCodes)
        var restrictedBlocks = self.blocksFor(restrictedCodes, maxCodes)

        var nextCode = self.config.nextCode ?? ""
        if let nextCheck = self.config.nextCodeWithCheck, restrictedCodes.count > 0 {
            nextCode = nextCheck
        }

        // if possible, merge the last regular and the last restricted block
        if regularBlocks.count > 1 && restrictedBlocks.count > 0 {
            let lastRegularBlock = regularBlocks.count - 1
            let lastRestrictedBlock = restrictedBlocks.count - 1
            if regularBlocks[lastRegularBlock].count + restrictedBlocks[lastRestrictedBlock].count <= maxCodes {
                restrictedBlocks[lastRestrictedBlock].append(contentsOf: regularBlocks[lastRegularBlock])
                regularBlocks.remove(at: lastRegularBlock)
            }
        }

        // append "nextCode" to all blocks but the last
        if nextCode.count > 0 {
            if regularBlocks.count > 0 {
                let upper = restrictedBlocks.count > 0 ? regularBlocks.count : regularBlocks.count - 1
                for i in 0 ..< upper {
                    regularBlocks[i].append(nextCode)
                }
            }

            if restrictedBlocks.count > 1 {
                for i in 0 ..< restrictedBlocks.count - 1 {
                    restrictedBlocks[i].append(nextCode)
                }
            }
        }

        // append "finalCode" to the last block
        if let final = self.config.finalCode {
            if restrictedBlocks.count > 0 {
                restrictedBlocks[restrictedBlocks.count - 1].append(final)
            } else {
                regularBlocks[regularBlocks.count - 1].append(final)
            }
        }

        if restrictedCodes.count > 0 && regularBlocks.count == 0 && nextCode.count > 0 {
            // there were no regular products, create a new regular block with just the `nextCodeCheck` code
            regularBlocks = [[nextCode]]
        }

        var codeblocks = regularBlocks
        codeblocks.append(contentsOf: restrictedBlocks)

//        for (index, block) in codeblocks.enumerated() {
//            Log.debug("block \(index): \(block.count) elements, first=\(block[0]), last=\(block[block.count-1])")
//        }

        return codeblocks
    }

    private func blocksFor(_ codes: [String], _ blockSize: Int) -> [[String]] {
        return stride(from: 0, to: codes.count, by: blockSize).map {
            Array(codes[$0 ..< min($0 + blockSize, codes.count)])
        }
    }
}
