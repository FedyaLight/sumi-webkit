//
//  BookmarksImportSummary.swift
//

import Foundation

public struct BookmarksImportSummary: Equatable, Sendable {
    public var successful: Int
    public var duplicates: Int
    public var failed: Int

    public init(successful: Int, duplicates: Int, failed: Int) {
        self.successful = successful
        self.duplicates = duplicates
        self.failed = failed
    }

}
