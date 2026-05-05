//
//  URLExtension.swift
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

extension URL {

    public static let empty = (NSURL(string: "") ?? NSURL()) as URL

    public var isEmpty: Bool {
        absoluteString.isEmpty
    }

    public func matches(_ other: URL) -> Bool {
        let string1 = self.absoluteString
        let string2 = other.absoluteString
        return string1.droppingHashedSuffix().dropping(suffix: "/").appending(string1.hashedSuffix ?? "")
            == string2.droppingHashedSuffix().dropping(suffix: "/").appending(string2.hashedSuffix ?? "")
    }

    public var root: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    public var securityOrigin: SecurityOrigin {
        SecurityOrigin(protocol: self.scheme ?? "",
                       host: self.host ?? "",
                       port: self.port ?? 0)
    }

    public func isPart(ofDomain domain: String) -> Bool {
        guard let host = host else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    public struct NavigationalScheme: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public static let separator = "://"

        public static let http = NavigationalScheme(rawValue: "http")
        public static let https = NavigationalScheme(rawValue: "https")
        public static let ftp = NavigationalScheme(rawValue: "ftp")
        public static let file = NavigationalScheme(rawValue: "file")
        public static let data = NavigationalScheme(rawValue: "data")
        public static let blob = NavigationalScheme(rawValue: "blob")
        public static let about = NavigationalScheme(rawValue: "about")
        public static let duck = NavigationalScheme(rawValue: "duck")
        public static let mailto = NavigationalScheme(rawValue: "mailto")
        public static let webkitExtension = NavigationalScheme(rawValue: "webkit-extension")

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public func separated() -> String {
            if case .mailto = self {
                return self.rawValue + ":"
            }
            return self.rawValue + Self.separator
        }
    }

    public var navigationalScheme: NavigationalScheme? {
        self.scheme.map(NavigationalScheme.init(rawValue:))
    }

    public func replacing(host: String?) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.host = host
        return components.url
    }

    public func appending(_ path: String) -> URL {
        appendingPathComponent(path)
    }

    /// returns true if URLs are equal except the #fragment part
    public func isSameDocument(_ other: URL) -> Bool {
        self.absoluteString.droppingHashedSuffix() == other.absoluteString.droppingHashedSuffix()
    }

    public enum URLProtocol: String {
        case http
        case https

        public var scheme: String {
            return "\(rawValue)://"
        }
    }

    public func toHttps() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        guard components.scheme == URLProtocol.http.rawValue else { return self }
        components.scheme = URLProtocol.https.rawValue
        return components.url
    }

    public func getQueryItems() -> [URLQueryItem]? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let encodedQuery = components.percentEncodedQuery
        else { return nil }
        components.percentEncodedQuery = encodedQuery.encodingPlusesAsSpaces()
        return components.queryItems ?? nil
    }

    public func getQueryItem(named name: String) -> URLQueryItem? {
        getQueryItems()?.first(where: { queryItem -> Bool in
            queryItem.name == name
        })
    }

    public func getParameter(named name: String) -> String? {
        getQueryItem(named: name)?.value
    }

}
