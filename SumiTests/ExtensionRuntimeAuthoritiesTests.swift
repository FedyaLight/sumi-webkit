import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeAuthoritiesTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testLifecycleReadinessPreservesFailureUntilExplicitRecovery() {
        let lifecycle = ExtensionRuntimeLifecycleAuthority()

        XCTAssertEqual(lifecycle.state, .idle)
        lifecycle.beginLoading()
        XCTAssertEqual(lifecycle.state, .loading)
        lifecycle.updateReadiness(isReady: true)
        XCTAssertEqual(lifecycle.state, .ready)

        lifecycle.markFailed()
        lifecycle.updateReadiness(isReady: true)
        XCTAssertEqual(lifecycle.state, .failed)

        lifecycle.beginLoading()
        lifecycle.updateReadiness(isReady: true)
        XCTAssertEqual(lifecycle.state, .ready)
        lifecycle.reset(extensionSupportAvailable: false)
        XCTAssertEqual(lifecycle.state, .unavailable)
    }

    func testDemandWithoutEnabledExtensionsIsStickyUntilReset() {
        let demand = ExtensionRuntimeDemandAuthority()

        XCTAssertFalse(
            demand.admitsRuntime(
                hasEnabledExtensions: false,
                allowWithoutEnabledExtensions: false
            )
        )
        demand.recordRuntimeDemandWithoutEnabledExtensions()
        XCTAssertTrue(
            demand.admitsRuntime(
                hasEnabledExtensions: false,
                allowWithoutEnabledExtensions: false
            )
        )

        demand.reset()
        XCTAssertFalse(
            demand.admitsRuntime(
                hasEnabledExtensions: false,
                allowWithoutEnabledExtensions: false
            )
        )
    }

    func testLoadStatusReportsOnlyRealTransitions() {
        let status = ExtensionRuntimeLoadStatusAuthority()

        XCTAssertTrue(status.markExtensionsLoaded())
        XCTAssertFalse(status.markExtensionsLoaded())
        XCTAssertTrue(status.extensionsLoaded)
        XCTAssertTrue(status.reset())
        XCTAssertFalse(status.reset())
        XCTAssertFalse(status.extensionsLoaded)
    }

    func testCatalogScopedRetirementAndResetPreserveUnrelatedResults() {
        let catalog = ExtensionRuntimeCatalog()
        let profileA = UUID()
        let profileB = UUID()
        catalog.recordManifest(["name": "alpha"], for: "alpha")
        catalog.recordManifest(["name": "beta"], for: "beta")
        catalog.recordLoadError(
            TestError.failed,
            extensionID: "alpha",
            profileID: profileA
        )
        catalog.recordLoadError(
            TestError.failed,
            extensionID: "alpha",
            profileID: profileB
        )
        catalog.recordLoadError(
            TestError.failed,
            extensionID: "beta",
            profileID: profileA
        )

        catalog.retire(extensionID: "alpha")

        XCTAssertNil(catalog.manifest(for: "alpha"))
        XCTAssertFalse(catalog.hasLoadErrors(for: "alpha"))
        XCTAssertEqual(
            catalog.manifest(for: "beta")?["name"] as? String,
            "beta"
        )
        XCTAssertNotNil(
            catalog.loadError(extensionID: "beta", profileID: profileA)
        )

        catalog.reset()
        XCTAssertTrue(catalog.isEmpty)
    }

    func testResidencyScopedRemovalRetirementAndResetPreserveUnrelatedEntries() {
        let residency = ExtensionRuntimeResidencyAuthority()
        let profileA = UUID()
        let profileB = UUID()
        residency.touch(extensionID: "alpha", profileID: profileA)
        residency.touch(extensionID: "alpha", profileID: profileB)
        residency.touch(extensionID: "beta", profileID: profileA)

        residency.remove(extensionID: "alpha", profileID: profileA)
        XCTAssertFalse(
            residency.liveContextKeys.contains(
                .init(profileId: profileA, extensionId: "alpha")
            )
        )
        XCTAssertTrue(
            residency.liveContextKeys.contains(
                .init(profileId: profileB, extensionId: "alpha")
            )
        )

        residency.retire(extensionID: "alpha")
        XCTAssertTrue(
            residency.liveContextKeys.allSatisfy {
                $0.extensionId != "alpha"
            }
        )
        XCTAssertEqual(residency.liveContextKeys.count, 1)

        residency.reset()
        XCTAssertTrue(residency.liveContextKeys.isEmpty)
    }

    func testMetricsSemanticUpdatesRemainScopedAndReset() {
        let metrics = ExtensionRuntimeMetricsAuthority()
        metrics.recordManifestValidationDuration(0.1, for: "alpha")
        metrics.recordContextLoadDuration(0.2, for: "alpha")
        metrics.recordBackgroundWake(
            duration: 0.3,
            reason: .nativeMessaging,
            didFail: true,
            for: "alpha"
        )
        metrics.recordWebExtensionCreationDuration(0.4, for: "beta")

        XCTAssertEqual(
            metrics.metrics(for: "alpha")?.manifestValidationDuration,
            0.1
        )
        XCTAssertEqual(metrics.metrics(for: "alpha")?.contextLoadDuration, 0.2)
        XCTAssertEqual(metrics.metrics(for: "alpha")?.backgroundWakeCount, 1)
        XCTAssertEqual(
            metrics.metrics(for: "alpha")?.lastBackgroundWakeReason,
            .nativeMessaging
        )
        XCTAssertEqual(
            metrics.metrics(for: "beta")?.webExtensionCreationDuration,
            0.4
        )

        metrics.reset()
        XCTAssertTrue(metrics.isEmpty)
    }

    func testLoadRevisionAdvanceInvalidatesCapturedRevision() {
        let revisions = ExtensionLoadRevisionAuthority()
        let captured = revisions.issue()

        let current = revisions.advance()

        XCTAssertFalse(revisions.isCurrent(captured))
        XCTAssertTrue(revisions.isCurrent(current))
    }

    func testTabPublicationCompareAndAdvanceRejectsStaleRevision() throws {
        let revisions = ExtensionTabPublicationRevisionAuthority()
        let captured = revisions.issue()
        let current = try XCTUnwrap(revisions.advance(ifCurrent: captured))

        XCTAssertFalse(revisions.isCurrent(captured))
        XCTAssertTrue(revisions.isCurrent(current))
        XCTAssertNil(revisions.advance(ifCurrent: captured))
        XCTAssertEqual(revisions.issue(), current)
    }

    func testPublicationEvidenceIsInvalidatedIndependentlyByEachRevision()
        throws {
        let loadRevisions = ExtensionLoadRevisionAuthority()
        let tabRevisions = ExtensionTabPublicationRevisionAuthority()
        let issuer = ExtensionRuntimePublicationEvidenceIssuer(
            extensionLoadRevisions: loadRevisions,
            tabPublicationRevisions: tabRevisions
        )
        let initial = issuer.issue()

        let tabAdvanced = try XCTUnwrap(
            issuer.advanceTabPublication(ifCurrent: initial)
        )
        XCTAssertFalse(issuer.isCurrent(initial))
        XCTAssertTrue(issuer.isCurrent(tabAdvanced))
        XCTAssertEqual(tabAdvanced.extensionLoad, initial.extensionLoad)

        loadRevisions.advance()
        XCTAssertFalse(issuer.isCurrent(tabAdvanced))
        XCTAssertNil(issuer.advanceTabPublication(ifCurrent: tabAdvanced))
        XCTAssertTrue(issuer.isCurrent(issuer.issue()))
    }
}
