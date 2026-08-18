import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiWebKitDiskCacheSizeObserverTests: XCTestCase {
    func testEmptyNonPersistentStoreReportsZeroWhenSizeSPIExists() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let selector = NSSelectorFromString(
            "_fetchDataRecordsOfTypes:withOptions:completionHandler:"
        )
        guard store.responds(to: selector) else {
            throw XCTSkip("WebKit size SPI is unavailable on this OS")
        }

        let size = await withCheckedContinuation { continuation in
            let scheduled = SumiFetchWKWebsiteDataStoreDiskCacheSize(
                store,
                5,
                { number in continuation.resume(returning: number?.uint64Value) }
            )
            if scheduled == false {
                continuation.resume(returning: nil)
            }
        }

        XCTAssertEqual(size, 0)
    }
}
