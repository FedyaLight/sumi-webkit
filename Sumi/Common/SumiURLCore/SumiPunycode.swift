import Foundation

/// RFC 3492 Punycode encoding of internationalized host labels ("xn--" form).
enum SumiPunycode {
    private static let base = 36
    private static let tMin = 1
    private static let tMax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN = 128
    private static let aceLabelPrefix = "xn--"

    /// Converts a full host to its ASCII (punycode) form, lowercasing labels.
    /// Returns nil when a label cannot be encoded.
    static func hostToASCII(_ host: String) -> String? {
        let labels = host.lowercased().components(separatedBy: ".")
        var asciiLabels: [String] = []
        asciiLabels.reserveCapacity(labels.count)

        for label in labels {
            if label.unicodeScalars.allSatisfy({ $0.isASCII }) {
                asciiLabels.append(label)
            } else {
                guard let encoded = encodeLabel(label) else { return nil }
                asciiLabels.append(aceLabelPrefix + encoded)
            }
        }

        return asciiLabels.joined(separator: ".")
    }

    private static func encodeLabel(_ label: String) -> String? {
        let input = Array(label.unicodeScalars.map { $0.value })
        var output: [Character] = input.compactMap { scalar in
            scalar < 128 ? Character(UnicodeScalar(scalar)!) : nil
        }

        let basicLength = output.count
        var handled = basicLength
        if basicLength > 0 {
            output.append("-")
        }

        var n = UInt32(initialN)
        var delta: UInt32 = 0
        var bias = initialBias

        while handled < input.count {
            guard let m = input.filter({ $0 >= n }).min() else { return nil }
            let (product, overflow) = (m - n).multipliedReportingOverflow(by: UInt32(handled + 1))
            if overflow { return nil }
            let (sum, sumOverflow) = delta.addingReportingOverflow(product)
            if sumOverflow { return nil }
            delta = sum
            n = m

            for scalar in input {
                if scalar < n {
                    let (next, deltaOverflow) = delta.addingReportingOverflow(1)
                    if deltaOverflow { return nil }
                    delta = next
                }
                guard scalar == n else { continue }

                var q = delta
                var k = base
                while true {
                    let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                    if q < UInt32(t) { break }
                    let code = UInt32(t) + (q - UInt32(t)) % UInt32(base - t)
                    output.append(digitCharacter(code))
                    q = (q - UInt32(t)) / UInt32(base - t)
                    k += base
                }

                output.append(digitCharacter(q))
                bias = adapt(delta: delta, numPoints: handled + 1, firstTime: handled == basicLength)
                delta = 0
                handled += 1
            }

            delta += 1
            n += 1
        }

        return String(output)
    }

    private static func digitCharacter(_ digit: UInt32) -> Character {
        if digit < 26 {
            return Character(UnicodeScalar(UInt8(97 + digit)))
        }
        return Character(UnicodeScalar(UInt8(48 + digit - 26)))
    }

    private static func adapt(delta: UInt32, numPoints: Int, firstTime: Bool) -> Int {
        var delta = firstTime ? delta / UInt32(damp) : delta / 2
        delta += delta / UInt32(numPoints)

        var k = 0
        while delta > UInt32((base - tMin) * tMax) / 2 {
            delta /= UInt32(base - tMin)
            k += base
        }

        return k + (base - tMin + 1) * Int(delta) / (Int(delta) + skew)
    }
}
