//
//  ContentBlockerRulesManager.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import WebKit

public enum ContentBlockerRulesManager {
    public typealias CompletionToken = String

        public struct Rules {
        public let name: String
        public let rulesList: WKContentRuleList
        public let etag: String
        public let identifier: ContentBlockerRulesIdentifier

        public init(
            name: String,
            rulesList: WKContentRuleList,
            etag: String,
            identifier: ContentBlockerRulesIdentifier
        ) {
            self.name = name
            self.rulesList = rulesList
            self.etag = etag
            self.identifier = identifier
        }
    }

    public struct UpdateEvent: CustomDebugStringConvertible {
        public let rules: [ContentBlockerRulesManager.Rules]
        public let changes: [String: ContentBlockerRulesIdentifier.Difference]
        public let completionTokens: [ContentBlockerRulesManager.CompletionToken]

        public init(
            rules: [ContentBlockerRulesManager.Rules],
            changes: [String: ContentBlockerRulesIdentifier.Difference],
            completionTokens: [ContentBlockerRulesManager.CompletionToken]
        ) {
            self.rules = rules
            self.changes = changes
            self.completionTokens = completionTokens
        }

        public var debugDescription: String {
            """
              rules: \(rules.map { "\($0.name):\($0.identifier) - \($0.rulesList) (\($0.etag))" }.joined(separator: ", "))
              changes: \(changes)
              completionTokens: \(completionTokens)
            """
        }
    }
}
