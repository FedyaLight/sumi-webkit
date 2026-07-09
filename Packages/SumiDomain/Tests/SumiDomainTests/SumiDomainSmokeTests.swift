import XCTest
import SumiDomain

final class SumiDomainSmokeTests: XCTestCase {
    func testPublicSuffixListLoadsBundledRules() {
        let list = SumiPublicSuffixList.bundled
        XCTAssertEqual(list.registrableDomain(forHost: "www.example.com"), "example.com")
    }

    func testSurfaceHelpersRecognizeEmptyTab() {
        XCTAssertTrue(SumiSurface.isEmptyNewTabURL(SumiSurface.emptyTabURL))
    }

    func testExtensionOwnedURLSchemes() {
        XCTAssertTrue(SumiExtensionOwnedURL.isExtensionOwnedURL(URL(string: "webkit-extension://ext-abc/")))
        XCTAssertFalse(SumiExtensionOwnedURL.isExtensionOwnedURL(URL(string: "https://example.com")))
    }

    func testShortcutPinRoleAndKeyCombination() {
        XCTAssertEqual(ShortcutPinRole.essential.rawValue, "essential")
        let combo = KeyCombination(key: "T", modifiers: [.command])
        XCTAssertEqual(combo.key, "t")
        XCTAssertEqual(combo.lookupKey, "cmd+t")
    }

    func testProfileIconAndURLNormalization() {
        XCTAssertTrue(SumiProfileIcon.usesDefaultIcon(""))
        XCTAssertEqual(
            SumiURLNormalization.normalizedStartupURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertEqual(
            SumiPermissionCoordinatorOutcome.granted.rawValue,
            "granted"
        )
    }

    func testProfilePartitionAndTabIdentityAreHashable() {
        let partition = ProfilePartition(name: "Work", icon: "💼", isEphemeral: false)
        XCTAssertEqual(partition.icon, "💼")
        XCTAssertFalse(partition.isEphemeral)

        let tab = TabIdentity(
            url: "https://example.com",
            title: "Example",
            spaceId: UUID(),
            profilePartitionId: partition.id,
            isPinned: true,
            folderId: nil
        )
        XCTAssertEqual(tab.profilePartitionId, partition.id)
        XCTAssertTrue(tab.isPinned)
        XCTAssertEqual(Set([partition, partition]).count, 1)
        XCTAssertEqual(Set([tab, tab]).count, 1)
    }

    @MainActor
    func testTabPlacementStateOwnerShortcutBinding() {
        let owner = TabPlacementStateOwner()
        let pinId = UUID()
        owner.bindToShortcutPin(id: pinId, role: .essential)
        XCTAssertEqual(owner.shortcutPinId, pinId)
        XCTAssertEqual(owner.shortcutPinRole, .essential)
        XCTAssertTrue(owner.isShortcutLiveInstance)
        owner.clearShortcutBinding()
        XCTAssertNil(owner.shortcutPinId)
        XCTAssertNil(owner.shortcutPinRole)
        XCTAssertFalse(owner.isShortcutLiveInstance)
    }
}
