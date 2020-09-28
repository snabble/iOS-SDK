//
//  GS1Code.swift
//
//  Copyright © 2020 snabble. All rights reserved.
//

import Foundation

// a parsed Application Identifier with it value(s)
public struct GS1CodeElement {
    public let definition: ApplicationIdentifier
    public let values: [String]

    private static let decimalPrefixes = Set(["31", "32", "33", "34", "35", "36", "39"])

    public var decimal: Decimal? {
        let pfx = String(definition.prefix.prefix(2))
        guard
            Self.decimalPrefixes.contains(pfx),
            let commaPosition = definition.prefix.last?.asciiValue,
            let value = values.last,
            let decimal = Decimal(string: value)
        else {
            return nil
        }

        let divisor = pow(Decimal(10), Int(commaPosition - 48))
        return decimal / divisor
    }
}

/// parse a GS1 barcode into its constituent application identifiers
///
/// any skipped/unknown/invalid code parts will be returned in `skipped`
public struct GS1Code {
    public static let gs = "\u{1d}"

    private static var prefixMap: [String: [ApplicationIdentifier]] = {
        var map = [String: [ApplicationIdentifier]]()
        for ai in ApplicationIdentifier.allIdentifiers {
            let pfx = String(ai.prefix.prefix(2))
            map[pfx, default: []].append(ai)
        }

        #if DEBUG
        for (key, values) in map {
            let len = values[0].prefix.count
            values.forEach {
                assert($0.prefix.count == len)
            }
        }
        #endif

        return map
    }()

    public private(set) var identifiers = [GS1CodeElement]()
    public private(set) var skipped = [String]()

    public init(_ code: String) {
        let (identifiers, skipped) = parse(code)
        self.identifiers = identifiers
        self.skipped = skipped
    }

    // MARK: - convenience accessors for often-used AIs

    public var gtin: String? {
        return valueForAI("01")
    }

    public func weight(in unit: Units) -> Decimal? {
        guard let rawWeight = firstDecimal(matching: "310") else {
            return nil
        }

        switch unit {
        case .kilogram: return rawWeight
        case .hectogram: return rawWeight * Decimal(10)
        case .decagram: return rawWeight * Decimal(100)
        case .gram: return rawWeight * Decimal(1000)
        default: return nil
        }
    }

    public func length(in unit: Units) -> Decimal? {
        guard let rawLength = firstDecimal(matching: "311") else {
            return nil
        }

        switch unit {
        case .meter: return rawLength
        case .decimeter: return rawLength * Decimal(10)
        case .centimeter: return rawLength * Decimal(100)
        case .millimeter: return rawLength * Decimal(1000)
        default: return nil
        }
    }

    public var amount: Int? {
        guard let amount = valueForAI("30") else {
            return nil
        }
        return Int(amount)
    }

    public var price: (price: Decimal, currency: String?)? {
        // try "amount payable (single monetary area)" first
        if let price = firstDecimal(matching: "392") {
            return (price, nil)
        }

        // try "amount payable with ISO currency code"
        if let priceAI = firstElement(matching: "393"), let price = priceAI.decimal {
            return (price, priceAI.values[0])
        }

        return nil
    }

    private func firstDecimal(matching prefix: String) -> Decimal? {
        return firstElement(matching: prefix)?.decimal
    }

    private func firstElement(matching prefix: String) -> GS1CodeElement? {
        for digit in (0...5).reversed() {
            let ai = "\(prefix)\(digit)"
            let match = self.identifiers.first { $0.definition.prefix == ai }
            if let identifier = match {
                return identifier
            }
        }

        return nil
    }

    private func valueForAI(_ ai: String) -> String? {
        return self.identifiers.first(where: { $0.definition.prefix == ai })?.values[0]
    }
}

// MARK: - parsing methods
extension GS1Code {

    static let symbologyIdentifiers = [
        "]C1",  // = GS1-128
        "]e0",  // = GS1 DataBar
        "]d2",  // = GS1 DataMatrix
        "]Q3",  // = GS1 QR Code
        "]J1"   // = GS1 DotCode
    ]

    private func parse(_ code: String) -> ([GS1CodeElement], [String]) {
        var code = code
        var identifiers = [GS1CodeElement]()
        var skipped = [String]()

        for symId in Self.symbologyIdentifiers {
            if code.hasPrefix(symId) {
                code.removeFirst(symId.count)
            }
        }

        while !code.isEmpty {
            while code.hasPrefix(Self.gs) {
                code.removeFirst()
            }

            let prefix = String(code.prefix(2))
            if let candidates = Self.prefixMap[prefix], let candidate = findCandidate(candidates, code) {
                if let (len, values) = self.matchCandidate(candidate, code) {
                    code.removeFirst(len)
                    let ai = GS1CodeElement(definition: candidate, values: values)
                    identifiers.append(ai)
                } else {
                    let skip = skipToNext(&code)
                    // print("unmatched pattern \(candidate.regex.pattern) - skipping over \(skip) to next FNC1")
                    skipped.append(skip)
                }
            } else {
                let skip = skipToNext(&code)
                // print("unknown prefix - skipping over \(skip) to next FNC1")
                skipped.append(skip)
            }
        }

        return (identifiers, skipped)
    }

    private func skipToNext(_ code: inout String) -> String {
        let prefix = String(code.prefix(2))
        if let length = ApplicationIdentifier.predefinedLengths[prefix] {
            let skipped = code.prefix(length)
            code.removeFirst(min(code.count, length))
            return String(skipped)
        } else {
            // skip until next separator
            var skipped = [Character]()
            while !code.hasPrefix(Self.gs) && !code.isEmpty {
                skipped.append(code.removeFirst())
            }
            return String(skipped)
        }
    }

    private func findCandidate(_ candidates: [ApplicationIdentifier], _ code: String) -> ApplicationIdentifier? {
        if candidates.count == 1 {
            return candidates[0]
        }

        for ai in candidates {
            if code.hasPrefix(ai.prefix) {
                return ai
            }
        }
        return nil
    }

    private func matchCandidate(_ ai: ApplicationIdentifier, _ code: String) -> (Int, [String])? {
        var len = 0
        var values = [String]()

        let matches = ai.regex.matches(in: code, options: [], range: NSRange(location: 0, length: code.count))
        if !matches.isEmpty && matches[0].numberOfRanges > 1 {
            for idx in 1 ..< matches[0].numberOfRanges {
                let range = matches[0].range(at: idx)
                let startIndex = code.index(code.startIndex, offsetBy: range.lowerBound)
                let endIndex = code.index(code.startIndex, offsetBy: range.upperBound)
                let substr = String(code[startIndex..<endIndex])
                // print("found match: \(ai.name) \(substr)")
                len += substr.count
                values.append(substr)
            }
            len += ai.prefix.count
        } else {
            return nil
        }

        return (len, values)
    }
}
