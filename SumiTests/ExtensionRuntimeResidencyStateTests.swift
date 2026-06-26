import Foundation
import XCTest

@testable import Sumi

final class ExtensionRuntimeResidencyStateTests: XCTestCase {
    func testScopedKeyRoundTripsProfileAndExtensionId() throws {
        let profileId = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let rawKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: "extension:with:colon",
            profileId: profileId
        )

        XCTAssertEqual(
            rawKey,
            "11111111-2222-3333-4444-555555555555:extension:with:colon"
        )

        let parsed = try XCTUnwrap(
            ExtensionRuntimeResidencyState.parseScopedKey(rawKey)
        )
        XCTAssertEqual(parsed.profileId, profileId)
        XCTAssertEqual(parsed.extensionId, "extension:with:colon")
        XCTAssertNil(ExtensionRuntimeResidencyState.parseScopedKey("missing-profile"))
        XCTAssertNil(ExtensionRuntimeResidencyState.parseScopedKey("not-a-uuid:extension"))
    }

    func testTouchMovesContextToMostRecentPosition() throws {
        let profileId = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        var state = ExtensionRuntimeResidencyState()

        state.touch(extensionId: "a", profileId: profileId)
        state.touch(extensionId: "b", profileId: profileId)
        state.touch(extensionId: "a", profileId: profileId)

        XCTAssertEqual(
            state.liveContextKeys.map(\.extensionId),
            ["b", "a"]
        )
    }

    func testEvictionCandidatesKeepCurrentContextAndUseOldestResidencyOrder() throws {
        let profileId = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        var state = ExtensionRuntimeResidencyState()

        state.touch(extensionId: "oldest", profileId: profileId)
        state.touch(extensionId: "middle", profileId: profileId)
        state.touch(extensionId: "current", profileId: profileId)

        let candidates = state.touchAndEvictionCandidates(
            loadedContextCount: 4,
            limit: 2,
            keepingExtensionId: "current",
            keepingProfileId: profileId
        )

        XCTAssertEqual(
            candidates.map(\.extensionId),
            ["oldest", "middle"]
        )
        XCTAssertEqual(
            state.liveContextKeys.map(\.extensionId),
            ["oldest", "middle", "current"]
        )
    }

    func testRemovalByExtensionIdDropsAllProfileResidencyEntries() throws {
        let profileA = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let profileB = try XCTUnwrap(UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        var state = ExtensionRuntimeResidencyState()

        state.touch(extensionId: "shared", profileId: profileA)
        state.touch(extensionId: "other", profileId: profileA)
        state.touch(extensionId: "shared", profileId: profileB)
        state.remove(extensionId: "shared")

        XCTAssertEqual(state.liveContextKeys.map(\.extensionId), ["other"])
        XCTAssertEqual(state.liveContextKeys.map(\.profileId), [profileA])
    }
}
