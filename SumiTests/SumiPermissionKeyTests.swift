import XCTest

@testable import Sumi

final class SumiPermissionKeyTests: XCTestCase {
    func testEquivalentOriginsProduceEqualPersistentIdentities() {
        let lhs = key(
            requesting: "https://Example.com:443/path",
            top: "https://Top.example:443",
            pageId: "page-a"
        )
        let rhs = key(
            requesting: "https://example.com/other",
            top: "https://top.example",
            pageId: "page-b"
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.persistentIdentity, rhs.persistentIdentity)
    }

    func testDifferentTopOriginsAreDistinct() {
        let lhs = key(top: "https://embedder-a.example")
        let rhs = key(top: "https://embedder-b.example")

        XCTAssertNotEqual(lhs.persistentIdentity, rhs.persistentIdentity)
        XCTAssertNotEqual(lhs, rhs)
    }

    func testDifferentProfilesAreDistinct() {
        let lhs = key(profile: "profile-a")
        let rhs = key(profile: "profile-b")

        XCTAssertNotEqual(lhs.persistentIdentity, rhs.persistentIdentity)
        XCTAssertNotEqual(lhs, rhs)
    }

    func testTransientPageIdDoesNotAlterPersistentIdentity() {
        let lhs = key(pageId: "page-a")
        let rhs = key(pageId: "page-b")

        XCTAssertEqual(lhs.persistentIdentity, rhs.persistentIdentity)
        XCTAssertEqual(lhs, rhs)
    }

    func testExternalSchemeIncludesSchemeIdentity() {
        let mailto = key(permissionType: .externalScheme("MailTo"))
        let tel = key(permissionType: .externalScheme("tel"))

        XCTAssertTrue(mailto.persistentIdentity.contains("external-scheme:mailto"))
        XCTAssertNotEqual(mailto.persistentIdentity, tel.persistentIdentity)
    }

    private func key(
        requesting: String = "https://request.example",
        top: String = "https://top.example",
        permissionType: SumiPermissionType = .camera,
        profile: String = "profile-a",
        pageId: String? = nil
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: requesting),
            topOrigin: SumiPermissionOrigin(string: top),
            permissionType: permissionType,
            profilePartitionId: profile,
            transientPageId: pageId
        )
    }
}
