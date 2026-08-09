//
//  FavoriteHintSettingsStoreTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class FavoriteHintSettingsStoreTests: XCTestCase {
    private let key = "settings.favorite.placeholderDismissedProfileIds"

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FavoriteHintSettingsStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> FavoriteHintSettingsStore {
        FavoriteHintSettingsStore(
            userDefaults: defaults,
            dismissedProfileIdsKey: key
        )
    }

    func testPlaceholderShowsForAnUntouchedProfile() {
        let store = makeStore(defaults: makeDefaults())

        XCTAssertTrue(store.showsPlaceholder(profileId: UUID()))
    }

    func testPlaceholderIsHiddenWithoutAResolvedProfile() {
        let store = makeStore(defaults: makeDefaults())

        XCTAssertFalse(store.showsPlaceholder(profileId: nil))
    }

    func testDismissalIsScopedToOneProfile() {
        let store = makeStore(defaults: makeDefaults())
        let dismissed = UUID()
        let other = UUID()

        store.dismissPlaceholder(profileId: dismissed)

        XCTAssertFalse(store.showsPlaceholder(profileId: dismissed))
        XCTAssertTrue(store.showsPlaceholder(profileId: other))
    }

    func testDismissalSurvivesAStoreRebuild() {
        let defaults = makeDefaults()
        let profileId = UUID()

        makeStore(defaults: defaults).dismissPlaceholder(profileId: profileId)

        let reloaded = makeStore(defaults: defaults)
        XCTAssertFalse(reloaded.showsPlaceholder(profileId: profileId))
    }

    func testRepeatedDismissalDoesNotDuplicateThePersistedEntry() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let profileId = UUID()

        store.dismissPlaceholder(profileId: profileId)
        store.dismissPlaceholder(profileId: profileId)

        XCTAssertEqual(defaults.stringArray(forKey: key), [profileId.uuidString])
    }

    func testUnparsableStoredIdsAreDroppedInsteadOfHidingEveryPlaceholder() {
        let defaults = makeDefaults()
        let valid = UUID()
        defaults.set(["not-a-uuid", "", valid.uuidString], forKey: key)

        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.dismissedProfileIds, [valid])
        XCTAssertFalse(store.showsPlaceholder(profileId: valid))
        XCTAssertTrue(store.showsPlaceholder(profileId: UUID()))
    }

    func testSettingsFacadeRoutesToTheStore() {
        let defaults = makeDefaults()
        let settings = SumiSettingsService(userDefaults: defaults)
        let profileId = UUID()

        XCTAssertTrue(settings.showsFavoritePlaceholder(profileId: profileId))

        settings.dismissFavoritePlaceholder(profileId: profileId)

        XCTAssertFalse(settings.showsFavoritePlaceholder(profileId: profileId))
    }
}
