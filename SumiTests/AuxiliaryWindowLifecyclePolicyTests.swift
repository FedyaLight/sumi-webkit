import XCTest

@testable import Sumi

final class AuxiliaryWindowLifecyclePolicyTests: XCTestCase {
    func testBulkCleanupNeverReactivatesBrowserWindows() {
        let bulkReasons: [AuxiliaryWindowCloseReason] = [
            .presentationFailure,
            .profileSwitch,
            .appQuit,
            .extensionDisable,
            .bulkCleanup,
        ]

        for reason in bulkReasons {
            XCTAssertFalse(reason.shouldRestoreOpenerFocus, "reason=\(reason)")
            XCTAssertFalse(reason.shouldRestoreExtensionFocus, "reason=\(reason)")
        }
    }

    func testUserScopedCloseRestoresFocusWithoutReclosingNativeWindow() {
        XCTAssertTrue(
            AuxiliaryWindowCloseReason.nativeClose.shouldRestoreOpenerFocus
        )
        XCTAssertFalse(
            AuxiliaryWindowCloseReason.nativeClose.shouldCloseNativeWindow
        )
        XCTAssertTrue(
            AuxiliaryWindowCloseReason.webViewDidClose.shouldCloseNativeWindow
        )
        XCTAssertTrue(
            AuxiliaryWindowCloseReason.extensionRequestedClose
                .shouldRestoreExtensionFocus
        )
    }

    func testNestedPopupPolicyRejectsBoundaryBeforePermissionWork() {
        let policy = AuxiliaryWindowNestingPolicy(maximumDepth: 3)

        XCTAssertEqual(policy.childDepth(after: 0), 1)
        XCTAssertEqual(policy.childDepth(after: 1), 2)
        XCTAssertNil(policy.childDepth(after: 2))
        XCTAssertFalse(policy.allowsPresentation(at: 3))
    }

    func testAuxiliaryIdentityPrefersOpenerAndKeepsMatchingSpace() {
        let explicitProfileID = UUID()
        let openerProfileID = UUID()
        let openerSpaceID = UUID()

        XCTAssertEqual(
            AuxiliaryWindowTabIdentityPolicy.resolve(
                explicitProfileID: nil,
                openerProfileID: openerProfileID,
                openerSpaceID: openerSpaceID,
                currentProfileID: UUID(),
                currentSpaceID: UUID(),
                currentSpaceProfileID: UUID()
            ),
            AuxiliaryWindowTabIdentity(
                profileID: openerProfileID,
                spaceID: openerSpaceID
            )
        )

        XCTAssertEqual(
            AuxiliaryWindowTabIdentityPolicy.resolve(
                explicitProfileID: explicitProfileID,
                openerProfileID: openerProfileID,
                openerSpaceID: openerSpaceID,
                currentProfileID: openerProfileID,
                currentSpaceID: openerSpaceID,
                currentSpaceProfileID: openerProfileID
            ),
            AuxiliaryWindowTabIdentity(
                profileID: explicitProfileID,
                spaceID: nil
            ),
            "A popup must not inherit a space from a different profile"
        )
    }

    func testAuxiliaryIdentityUsesCurrentMatchingSpaceWithoutOpener() {
        let profileID = UUID()
        let spaceID = UUID()

        XCTAssertEqual(
            AuxiliaryWindowTabIdentityPolicy.resolve(
                explicitProfileID: profileID,
                openerProfileID: nil,
                openerSpaceID: nil,
                currentProfileID: nil,
                currentSpaceID: spaceID,
                currentSpaceProfileID: profileID
            ),
            AuxiliaryWindowTabIdentity(
                profileID: profileID,
                spaceID: spaceID
            )
        )
    }
}
