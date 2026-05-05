//
//  StringExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Punycode

public typealias RegEx = NSRegularExpression

public func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    return (try? NSRegularExpression(pattern: pattern, options: options))!
}

public extension String {

    static let localhost = "localhost"

    // MARK: Prefix/Suffix

    func dropping(prefix: String) -> String {
        return hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func dropping(suffix: String) -> String {
        return hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    func droppingWwwPrefix() -> String {
        self.dropping(prefix: "www.")
    }

    var hashedSuffixRange: PartialRangeFrom<String.Index>? {
        if let idx = self.firstIndex(of: "#") {
            return idx...
        } else if self.hasPrefix("about:"),
                  let range = self.range(of: "%23") {
            return range.lowerBound...
        }
        return nil
    }

    var hashedSuffix: String? {
        hashedSuffixRange.map { range in String(self[range]) }
    }

    func droppingHashedSuffix() -> String {
        if let range = self.hashedSuffixRange {
            guard range.lowerBound > self.startIndex else { return "" }
            return String(self[..<range.lowerBound])
        }
        return self
    }

    // MARK: Regex

    func replacing(_ regex: RegEx, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: self, range: self.fullRange, withTemplate: replacement)
    }

    func replacing(regex pattern: String, with replacement: String) -> String {
        self.replacing(regex(pattern), with: replacement)
    }

    // MARK: Replacements

    /// Replaces all occurrences of the given keys with their values in a single pass.
    ///
    /// Scans the string's UTF-8 bytes once, matching replacement keys at each position
    /// and copying non-matching regions in bulk. Replacement values are never re-expanded.
    /// Longer keys are matched first to avoid partial matches.
    func applyingReplacements(_ replacements: [String: String]) -> String {
        guard !replacements.isEmpty else { return self }

        let templateUTF8 = Array(self.utf8)
        let keys = replacements
            .filter { !$0.key.isEmpty }
            .map { (utf8: Array($0.key.utf8), value: Array($0.value.utf8)) }
            .sorted { $0.utf8.count > $1.utf8.count }

        guard !keys.isEmpty else { return self }

        let firstBytes = Set(keys.map { $0.utf8[0] })

        var result = [UInt8]()
        result.reserveCapacity(templateUTF8.count)

        var i = 0
        while i < templateUTF8.count {
            if firstBytes.contains(templateUTF8[i]) {
                var matched = false
                for entry in keys {
                    let end = i + entry.utf8.count
                    if end <= templateUTF8.count,
                       templateUTF8[i..<end].elementsEqual(entry.utf8) {
                        result.append(contentsOf: entry.value)
                        i = end
                        matched = true
                        break
                    }
                }
                if !matched {
                    result.append(templateUTF8[i])
                    i += 1
                }
            } else {
                let start = i
                while i < templateUTF8.count && !firstBytes.contains(templateUTF8[i]) {
                    i += 1
                }
                result.append(contentsOf: templateUTF8[start..<i])
            }
        }

        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: result, as: UTF8.self)
    }

}

public extension StringProtocol {

    var utf8data: Data {
        data(using: .utf8)!
    }

    var fullRange: NSRange {
        NSRange(startIndex..<endIndex, in: self)
    }

    func encodingPlusesAsSpaces() -> String {
        return replacingOccurrences(of: "+", with: "%20")
    }

    var punycodeEncodedHostname: String {
        return self.split(separator: ".")
            .map { String($0) }
            .map { $0.idnaEncoded ?? $0 }
            .joined(separator: ".")
    }

    func trimmingWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
