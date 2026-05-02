//
//  NavigationHistoryContextMenu.swift
//  Sumi
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import Foundation

enum NavigationHistoryDisplayTitle {
    static func resolve(
        cachedTitle: String?,
        rawTitle: String?,
        url: URL?
    ) -> String {
        let normalizedCachedTitle = cachedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedCachedTitle, !normalizedCachedTitle.isEmpty {
            return normalizedCachedTitle
        }

        let normalizedRawTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedRawTitle, !normalizedRawTitle.isEmpty {
            return normalizedRawTitle
        }

        return url?.host ?? "Untitled"
    }
}
