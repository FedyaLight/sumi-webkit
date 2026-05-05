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

public extension String {

    // MARK: Prefix/Suffix

    func dropping(suffix: String) -> String {
        return hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
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
}

public extension StringProtocol {

    func trimmingWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
