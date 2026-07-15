import Foundation
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionToolbarPinningOwnerTests: XCTestCase {
    func testPinsAreOwnedPerProfileAndPersisted() throws {
        let suiteName = "SumiTests.ExtensionToolbarPinningOwner.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let firstProfileId = UUID()
        let secondProfileId = UUID()
        var currentProfileId: UUID? = firstProfileId
        var publishedPinnedIDs: [String] = []
        let installedIDs: Set<String> = ["extension-a", "extension-b"]

        func makeOwner() -> ExtensionToolbarPinningOwner {
            ExtensionToolbarPinningOwner(
                preferences: preferences,
                currentProfileId: { currentProfileId },
                installedExtensionIDs: { installedIDs },
                publishedPinnedIDs: { publishedPinnedIDs },
                setPublishedPinnedIDs: { publishedPinnedIDs = $0 }
            )
        }

        let owner = makeOwner()
        owner.pinToToolbar("extension-a", profileId: firstProfileId)
        owner.pinToToolbar("extension-a", profileId: firstProfileId)

        XCTAssertEqual(publishedPinnedIDs, ["extension-a"])
        XCTAssertEqual(
            owner.pinnedToolbarExtensionIDsByProfile[
                ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: firstProfileId)
            ],
            ["extension-a"]
        )

        currentProfileId = secondProfileId
        owner.reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertTrue(publishedPinnedIDs.isEmpty)

        owner.pinToToolbar("extension-b", profileId: secondProfileId)
        XCTAssertEqual(publishedPinnedIDs, ["extension-b"])

        publishedPinnedIDs = []
        let reloadedOwner = makeOwner()

        currentProfileId = firstProfileId
        reloadedOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertEqual(publishedPinnedIDs, ["extension-a"])

        currentProfileId = secondProfileId
        reloadedOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertEqual(publishedPinnedIDs, ["extension-b"])
    }

    func testReplacingProfileStateNormalizesPublishesAndPersists() throws {
        let suiteName = "SumiTests.ExtensionToolbarPinningOwner.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let profileId = UUID()
        let profileKey = ExtensionToolbarPinningOwner.pinnedToolbarProfileKey(for: profileId)
        var publishedPinnedIDs: [String] = []

        func makeOwner() -> ExtensionToolbarPinningOwner {
            ExtensionToolbarPinningOwner(
                preferences: preferences,
                currentProfileId: { profileId },
                installedExtensionIDs: { [] },
                publishedPinnedIDs: { publishedPinnedIDs },
                setPublishedPinnedIDs: { publishedPinnedIDs = $0 }
            )
        }

        let owner = makeOwner()
        owner.replacePinnedToolbarExtensionIDsByProfile([
            profileKey: [" extension-a ", "", "extension-a", "extension-b"],
        ])

        XCTAssertEqual(publishedPinnedIDs, ["extension-a", "extension-b"])
        XCTAssertEqual(
            owner.pinnedToolbarExtensionIDsByProfile[profileKey],
            ["extension-a", "extension-b"]
        )

        publishedPinnedIDs = []
        makeOwner().reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertEqual(publishedPinnedIDs, ["extension-a", "extension-b"])
    }
}
