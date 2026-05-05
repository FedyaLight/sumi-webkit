//
//  TLD.swift
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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
import URLPredictor

public class TLD {

    static let tlds: Set<String> = {
        guard let pslString = try? Classifier.getPSLData() else { return [] }

        var tlds: [String] = []
        pslString.enumerateLines { line, _ in
            let trimmed = line.trimmingWhitespace()
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else {
                return
            }
            tlds.append(trimmed)
        }
        return Set(tlds)
    }()

    public init() {}

    /// Return valid domain, stripping subdomains of given entity if possible.
    ///
    /// 'test.example.co.uk' -> 'example.co.uk'
    /// 'example.co.uk' -> 'example.co.uk'
    /// 'co.uk' -> 'co.uk'
    public func domain(_ host: String?) -> String? {
        guard let host = host else { return nil }

        let parts = [String](host.components(separatedBy: ".").reversed())

        var stack = ""

        var knownTLDFound = false
        for part in parts {
            stack = !stack.isEmpty ? part + "." + stack : part

            if Self.tlds.contains(stack) {
                knownTLDFound = true
            } else if knownTLDFound {
                break
            }
        }

        // If host does not contain tld treat it as invalid
        if knownTLDFound {
            return stack
        } else {
            return nil
        }
    }

    /// Return eTLD+1 (entity top level domain + 1) strictly.
    ///
    /// 'test.example.co.uk' -> 'example.co.uk'
    /// 'example.co.uk' -> 'example.co.uk'
    /// 'co.uk' -> nil
    public func eTLDplus1(_ host: String?) -> String? {
        guard let domain = domain(host), !Self.tlds.contains(domain) else { return nil }
        return domain
    }

}
