import XCTest

@testable import Sumi

@MainActor
final class ExtensionRuntimeMutationRegistryTests: XCTestCase {
    func testSameExtensionMutationFailsBusyUntilCurrentLeaseFinishes()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let install = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .install)
        )

        XCTAssertNil(
            registry.begin(extensionID: "alpha", operation: .enable)
        )
        XCTAssertNil(
            registry.begin(extensionID: "alpha", operation: .disable)
        )
        XCTAssertTrue(registry.isCurrent(install))
        XCTAssertTrue(registry.finish(install))
        XCTAssertFalse(registry.isCurrent(install))
        XCTAssertNotNil(
            registry.begin(extensionID: "alpha", operation: .uninstall)
        )
    }

    func testDifferentExtensionsHoldParallelScopedLeases() throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let alpha = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .install)
        )
        let beta = try XCTUnwrap(
            registry.begin(extensionID: "beta", operation: .enable)
        )

        XCTAssertTrue(registry.isCurrent(alpha))
        XCTAssertTrue(registry.isCurrent(beta))
        XCTAssertTrue(registry.finish(alpha))
        XCTAssertTrue(registry.isCurrent(beta))
        XCTAssertTrue(registry.finish(beta))
    }

    func testLoadAdmissionRequiresMatchingScopedLease() throws {
        let registry = ExtensionRuntimeMutationRegistry()
        XCTAssertTrue(registry.admitsLoad(extensionID: "free", lease: nil))

        let alpha = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .install)
        )
        let beta = try XCTUnwrap(
            registry.begin(extensionID: "beta", operation: .enable)
        )

        XCTAssertTrue(
            registry.admitsLoad(extensionID: "alpha", lease: alpha)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "alpha", lease: nil)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "alpha", lease: beta)
        )
        XCTAssertTrue(
            registry.admitsLoad(extensionID: "beta", lease: beta)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "free", lease: alpha)
        )
    }

    func testTerminalLeaseSupersedesScopedLeasesAndBlocksAllLoads()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let alpha = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .disable)
        )
        let beta = try XCTUnwrap(
            registry.begin(extensionID: "beta", operation: .uninstall)
        )

        let terminal = try XCTUnwrap(registry.beginTerminal())

        XCTAssertTrue(registry.isCurrent(terminal))
        XCTAssertFalse(registry.isCurrent(alpha))
        XCTAssertFalse(registry.isCurrent(beta))
        XCTAssertFalse(registry.finish(alpha))
        XCTAssertFalse(registry.finish(beta))
        XCTAssertNil(
            registry.begin(extensionID: "gamma", operation: .install)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "alpha", lease: alpha)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "alpha", lease: nil)
        )
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "gamma", lease: nil)
        )
    }

    func testFinishingTerminalLeaseReopensScopedMutationsAndLoads()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let terminal = try XCTUnwrap(registry.beginTerminal())

        XCTAssertTrue(registry.finish(terminal))
        XCTAssertFalse(registry.isCurrent(terminal))
        XCTAssertFalse(registry.finish(terminal))
        XCTAssertTrue(registry.admitsLoad(extensionID: "alpha", lease: nil))

        let scoped = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .enable)
        )
        XCTAssertTrue(registry.isCurrent(scoped))
        XCTAssertTrue(
            registry.admitsLoad(extensionID: "alpha", lease: scoped)
        )
    }

    func testSupersededTerminalLeaseCannotReopenCurrentTerminalSeal()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let superseded = try XCTUnwrap(registry.beginTerminal())
        let current = try XCTUnwrap(registry.beginTerminal())

        XCTAssertFalse(registry.isCurrent(superseded))
        XCTAssertTrue(registry.isCurrent(current))
        XCTAssertFalse(registry.finish(superseded))
        XCTAssertTrue(registry.isCurrent(current))
        XCTAssertFalse(
            registry.admitsLoad(extensionID: "alpha", lease: nil)
        )
        XCTAssertNil(
            registry.begin(extensionID: "alpha", operation: .enable)
        )

        XCTAssertTrue(registry.finish(current))
        XCTAssertTrue(registry.admitsLoad(extensionID: "alpha", lease: nil))
    }

    func testIrreversibleMutationBlocksForcedAndIdleTerminalAdmission()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let uninstall = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .uninstall)
        )

        XCTAssertTrue(registry.enterIrreversiblePhase(uninstall))
        XCTAssertNil(registry.beginTerminal())
        XCTAssertNil(registry.beginTerminalIfNoScopedMutations())
        XCTAssertTrue(registry.isCurrent(uninstall))
        XCTAssertTrue(registry.finish(uninstall))
        XCTAssertNotNil(registry.beginTerminal())
    }

    func testIdleTerminalAdmissionDoesNotSupersedeUnrelatedMutation()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let install = try XCTUnwrap(
            registry.begin(extensionID: "beta", operation: .install)
        )

        XCTAssertNil(registry.beginTerminalIfNoScopedMutations())
        XCTAssertTrue(registry.isCurrent(install))
        XCTAssertNotNil(registry.beginTerminal())
        XCTAssertFalse(registry.isCurrent(install))
    }

    func testTerminalAdmissionWaiterRunsAfterLastIrreversibleLease()
        throws {
        let registry = ExtensionRuntimeMutationRegistry()
        let alpha = try XCTUnwrap(
            registry.begin(extensionID: "alpha", operation: .uninstall)
        )
        let beta = try XCTUnwrap(
            registry.begin(extensionID: "beta", operation: .uninstall)
        )
        XCTAssertTrue(registry.enterIrreversiblePhase(alpha))
        XCTAssertTrue(registry.enterIrreversiblePhase(beta))
        var notificationCount = 0
        registry.runWhenTerminalAdmissionAvailable {
            notificationCount += 1
        }

        XCTAssertTrue(registry.finish(alpha))
        XCTAssertEqual(notificationCount, 0)
        XCTAssertTrue(registry.finish(beta))
        XCTAssertEqual(notificationCount, 1)
        XCTAssertFalse(registry.finish(beta))
        XCTAssertEqual(notificationCount, 1)
    }

    func testTerminalAdmissionWaiterRunsImmediatelyWithoutIrreversibleWork() {
        let registry = ExtensionRuntimeMutationRegistry()
        var didRun = false

        registry.runWhenTerminalAdmissionAvailable {
            didRun = true
        }

        XCTAssertTrue(didRun)
    }
}
