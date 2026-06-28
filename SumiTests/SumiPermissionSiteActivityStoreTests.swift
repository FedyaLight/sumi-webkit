import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionSiteActivityStoreTests: XCTestCase {
    func testUnreadablePersistentPayloadIsPreservedForDiagnostics() throws {
        let suiteName = "SumiSiteActivityStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let storageKey = "permissions.siteActivity.v1"
        let unreadablePayload = Data("not-json".utf8)
        defaults.set(unreadablePayload, forKey: storageKey)

        _ = SumiPermissionSiteActivityStore(userDefaults: defaults)

        XCTAssertEqual(defaults.data(forKey: "\(storageKey).unreadable"), unreadablePayload)
    }
}
