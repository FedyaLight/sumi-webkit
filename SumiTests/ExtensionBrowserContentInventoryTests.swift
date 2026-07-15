import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserDirectionalRoleTests: XCTestCase {
    func testTabInventoryPreservesCanonicalOrderAndIdentity() {
        let first = Tab()
        let duplicate = first
        let second = Tab()
        let tabs = BrowserExtensionTabQueryAdapter(
            regularTab: { _ in nil },
            allTabs: { [first, duplicate, second] },
            windows: { [] },
            isTransient: { _ in false },
            isAuxiliaryMiniWindow: { _ in false },
            isPinned: { _ in false }
        )

        XCTAssertEqual(
            tabs.allExtensionTabs.map(ObjectIdentifier.init),
            [first, second].map(ObjectIdentifier.init)
        )
    }

    func testTabQueryRejectsUnknownIdentityAndFindsEphemeralTab() {
        let regular = Tab()
        let ephemeral = Tab()
        let window = BrowserWindowState()
        window.appendEphemeralTab(ephemeral)
        let tabs = BrowserExtensionTabQueryAdapter(
            regularTab: { $0 == regular.id ? regular : nil },
            allTabs: { [regular, ephemeral] },
            windows: { [window] },
            isTransient: { _ in false },
            isAuxiliaryMiniWindow: { _ in false },
            isPinned: { _ in false }
        )

        XCTAssertIdentical(tabs.extensionTab(for: regular.id), regular)
        XCTAssertIdentical(tabs.extensionTab(for: ephemeral.id), ephemeral)
        XCTAssertNil(tabs.extensionTab(for: UUID()))
    }

    func testBrowserAvailabilityDoesNotMaterializeAnyOtherRole() {
        var availabilityReads = 0
        let availability = ExtensionBrowserRuntimeAvailability {
            availabilityReads += 1
            return false
        }

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availabilityReads, 1)
    }
}
