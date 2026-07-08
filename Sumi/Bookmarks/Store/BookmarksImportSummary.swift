//
//  BookmarksImportSummary.swift
//
//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//

import Foundation

struct BookmarksImportSummary: Equatable, Sendable {
    var successful: Int
    var duplicates: Int
    var failed: Int

    init(successful: Int, duplicates: Int, failed: Int) {
        self.successful = successful
        self.duplicates = duplicates
        self.failed = failed
    }

}
