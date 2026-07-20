import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class EssentialsShortcutPlacementCapacityTests: XCTestCase {
    func testSplitMembersConsumeOneVisualSlotButStandaloneItemsStillRespectGridCapacity()
        throws {
        let browser = BrowserManager()
        browser.tabRuntimeLifecycle.shutdown()
        let profile = Profile(name: "Profile")
        browser.profileManager.profiles = [profile]
        let pins = try (0..<EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems)
            .map { index in
                try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
                    ShortcutPin(
                        id: UUID(),
                        role: .essential,
                        profileId: profile.id,
                        index: index,
                        launchURL: URL(
                            string: "https://essential-\(index).example"
                        )!,
                        title: "Essential \(index)"
                    ),
                    at: index,
                    openTargetFolder: false
                ))
            }
        let placement = EssentialsShortcutPlacementOwner(
            spaces: browser.spaceStateOwner,
            runtimeConnection: browser.runtimePortConnection,
            pins: browser.shortcutPinCollectionStateOwner,
            splitGroups: browser.splitGroupStore
        )
        let context = EssentialsShortcutPlacementOwner.TargetContext(
            profileId: profile.id
        )
        let newURL = URL(string: "https://new.example")!

        XCTAssertFalse(placement.canAddURL(newURL, using: context))

        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.prefix(2).map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .essentialSidebar(profileId: profile.id, index: 0)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))

        XCTAssertTrue(placement.canAddURL(newURL, using: context))
        XCTAssertNotNil(placement.resolveInsertion(using: .init(
            target: context,
            targetIndex: nil,
            movingPinId: nil
        )))
    }
}
