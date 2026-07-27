import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationFailureSettlementTests: XCTestCase {
    func testCopiedRollbackRestoresPackageBeforePreviousRuntime() async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        let previous = ExtensionInstallationRuntimeReplacement.PreviousRuntime(
            entity: InstalledExtensionMetadata(record: harness.original),
            profileIDs: [UUID()],
            shouldRecover: true
        )

        let result = await harness.settlement.settle(
            harness.context(
                error: SettlementError.injected,
                candidate: nil,
                previousRuntime: previous
            )
        )

        XCTAssertEqual(result as? SettlementError, .injected)
        XCTAssertEqual(
            harness.events.values,
            ["package.rollback", "runtime.recover"]
        )
        XCTAssertEqual(harness.collection.records.first?.name, "Original")
    }

    func testPackageRollbackFailurePreventsUnsafeRuntimeRecovery()
        async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        harness.package.rollbackError = SettlementError.packageRollback
        let previous = ExtensionInstallationRuntimeReplacement.PreviousRuntime(
            entity: InstalledExtensionMetadata(record: harness.original),
            profileIDs: [UUID()],
            shouldRecover: true
        )

        let result = await harness.settlement.settle(
            harness.context(
                error: SettlementError.injected,
                candidate: nil,
                previousRuntime: previous
            )
        )

        XCTAssertEqual(harness.events.values, ["package.rollback"])
        XCTAssertTrue(
            result.localizedDescription.contains("package rollback failed"),
            result.localizedDescription
        )
    }

    func testExternalSafariRollbackNeverPretendsToRecoverOldBytes()
        async throws {
        let harness = makeHarness(packageOwnership: .externalSafariBundle)
        let previous = ExtensionInstallationRuntimeReplacement.PreviousRuntime(
            entity: InstalledExtensionMetadata(record: harness.original),
            profileIDs: [UUID()],
            shouldRecover: true
        )

        let result = await harness.settlement.settle(
            harness.context(
                error: SettlementError.injected,
                candidate: nil,
                previousRuntime: previous
            )
        )

        XCTAssertEqual(result as? SettlementError, .injected)
        XCTAssertTrue(harness.events.values.isEmpty)
    }

    func testExactRuntimeDurablyCommitsBeforePreservingPackage() async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        let candidate = makeRecord(name: "Candidate")

        let result = await harness.settlement.settle(
            harness.context(
                error: transactionFailure(.preserveForExactRuntime),
                candidate: candidate,
                previousRuntime: nil
            )
        )

        XCTAssertEqual(
            harness.events.values,
            ["record.persist:Candidate", "catalog.publish", "package.commit"]
        )
        XCTAssertEqual(harness.collection.records.first?.name, "Candidate")
        XCTAssertEqual(
            harness.collection.recordDurability(for: candidate.id),
            .durable
        )
        XCTAssertTrue(
            result.localizedDescription.contains(
                "candidate metadata were preserved durably"
            ),
            result.localizedDescription
        )
    }

    func testExactRuntimePersistenceFailurePublishesObservableVolatileRecord()
        async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        harness.persistence.persistError = SettlementError.persistence
        let candidate = makeRecord(name: "Candidate")

        let result = await harness.settlement.settle(
            harness.context(
                error: transactionFailure(.preserveForExactRuntime),
                candidate: candidate,
                previousRuntime: nil
            )
        )

        XCTAssertEqual(
            harness.events.values,
            [
                "record.persist:Candidate",
                "record.restore:Original",
                "catalog.publish",
                "package.commit",
            ]
        )
        XCTAssertEqual(
            harness.collection.recordDurability(for: candidate.id),
            .volatileExactRuntime
        )
        XCTAssertTrue(
            result.localizedDescription.contains("volatile live-catalog"),
            result.localizedDescription
        )
    }

    func testOtherRuntimeAuthoritiesPreservePackageWithoutPublishingCandidate()
        async throws {
        let dispositions: [ExternalStateRollbackDisposition] = [
            .preserveForReplacement,
            .preserveForActiveBinding,
            .preserveForCompetingTransaction,
            .preserveUntilSharedCleanup,
        ]
        for disposition in dispositions {
            let harness = makeHarness(packageOwnership: .copiedDirectory)

            _ = await harness.settlement.settle(
                harness.context(
                    error: transactionFailure(disposition),
                    candidate: makeRecord(name: "Candidate"),
                    previousRuntime: nil
                )
            )

            XCTAssertEqual(
                harness.events.values,
                ["package.commit"],
                "\(disposition)"
            )
            XCTAssertEqual(
                harness.collection.records.first?.name,
                "Original",
                "\(disposition)"
            )
        }
    }

    func testActivationRollbackAuthorityOverridesOriginalErrorDisposition()
        async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        let candidate = makeRecord(name: "Candidate")
        let exactRuntimeRollback = transactionFailure(
            .preserveForExactRuntime
        ).rollback

        _ = await harness.settlement.settle(
            harness.context(
                error: SettlementError.injected,
                candidate: candidate,
                previousRuntime: nil,
                runtimeRollback: exactRuntimeRollback
            )
        )

        XCTAssertEqual(
            harness.events.values,
            [
                "runtime.rollback",
                "record.persist:Candidate",
                "catalog.publish",
                "package.commit",
            ]
        )
        XCTAssertEqual(harness.collection.records.first?.name, "Candidate")
    }

    func testRecordRestorationFailureIsReportedAsIndeterminateMetadata()
        async throws {
        let harness = makeHarness(packageOwnership: .copiedDirectory)
        let commitFailure = ExtensionInstallationRecordTransaction.CommitFailure(
            persistenceError: SettlementError.persistence,
            restorationError: SettlementError.restoration
        )

        let result = await harness.settlement.settle(
            harness.context(
                error: commitFailure,
                candidate: nil,
                previousRuntime: nil
            )
        )

        XCTAssertTrue(
            result.localizedDescription.contains(
                "persisted metadata state is indeterminate"
            ),
            result.localizedDescription
        )
    }

    private func makeHarness(
        packageOwnership: ExtensionInstallationPackage.Ownership
    ) -> SettlementHarness {
        let events = SettlementEventLog()
        let collection = InstalledExtensionCollection()
        collection.connectRecordChanges {
            events.values.append("catalog.publish")
        }
        let original = makeRecord(name: "Original")
        collection.upsert(original)
        events.values.removeAll()
        let persistence = SettlementPersistence(events: events)
        let recordTransaction = ExtensionInstallationRecordTransaction(
            persistence: persistence,
            installedRecords: collection
        )
        let package = SettlementPackage(
            ownership: packageOwnership,
            events: events
        )
        let recovery = SettlementRuntimeRecovery(events: events)
        let registry = ExtensionRuntimeMutationRegistry()
        let lease = registry.begin(
            extensionID: original.id,
            operation: .install
        )!
        return SettlementHarness(
            events: events,
            collection: collection,
            original: original,
            persistence: persistence,
            package: package,
            settlement: ExtensionInstallationFailureSettlement(
                recordTransaction: recordTransaction,
                runtimeReplacement: recovery
            ),
            mutationLease: lease
        )
    }

    private func transactionFailure(
        _ disposition: ExternalStateRollbackDisposition
    ) -> ExtensionRuntimeTransactionFailure {
        let exact: ExtensionLoadedContextAuthority.ExactRollbackDisposition
        let shared:
            ExtensionLoadedContextAuthority.SharedCleanupDisposition
        switch disposition {
        case .rollbackAllowed:
            exact = .retired
            shared = .completed
        case .preserveForExactRuntime:
            exact = .exactBindingRemaining
            shared = .notAttempted
        case .preserveForReplacement:
            exact = .replacementPresent
            shared = .notAttempted
        case .preserveForActiveBinding:
            exact = .retired
            shared = .preservedForActiveBindings
        case .preserveForCompetingTransaction:
            exact = .retired
            shared = .preservedForCompetingTransaction
        case .preserveUntilSharedCleanup:
            exact = .retired
            shared = .notAttempted
        }
        return ExtensionRuntimeTransactionFailure(
            operationError: SettlementError.injected,
            rollback: .init(
                outcome: .retired,
                key: .init(
                    profileId: UUID(),
                    extensionId: "com.example.transaction"
                ),
                exactDisposition: exact,
                sharedCleanupDisposition: shared
            )
        )
    }

    private func makeRecord(name: String) -> InstalledExtension {
        InstalledExtension(
            id: "com.example.transaction",
            name: name,
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(timeIntervalSince1970: 1),
            lastUpdateDate: Date(timeIntervalSince1970: 2),
            packagePath: "/tmp/com.example.transaction",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: name,
            sourceBundlePath: "/tmp/source",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: .init(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [
                "manifest_version": 3,
                "name": name,
                "version": "1.0",
            ]
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private struct SettlementHarness {
    let events: SettlementEventLog
    let collection: InstalledExtensionCollection
    let original: InstalledExtension
    let persistence: SettlementPersistence
    let package: SettlementPackage
    let settlement: ExtensionInstallationFailureSettlement
    let mutationLease: ExtensionRuntimeMutationLease

    func context(
        error: any Error,
        candidate: InstalledExtension?,
        previousRuntime:
            ExtensionInstallationRuntimeReplacement.PreviousRuntime?,
        runtimeRollback:
            ExtensionLoadedContextAuthority.RollbackResult? = nil
    ) -> ExtensionInstallationFailureSettlement.Context {
        .init(
            error: error,
            package: package,
            recordSnapshot: .init(
                extensionID: original.id,
                originalRecord: original
            ),
            candidateRecord: candidate,
            previousRuntime: previousRuntime,
            rollbackRuntimeActivation: runtimeRollback.map { result in
                { @MainActor @Sendable in
                    events.values.append("runtime.rollback")
                    return result
                }
            },
            mutationLease: mutationLease
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class SettlementPackage:
    ExtensionInstallationPackageSettling {
    let ownership: ExtensionInstallationPackage.Ownership
    var rollbackError: (any Error)?
    private let events: SettlementEventLog

    init(
        ownership: ExtensionInstallationPackage.Ownership,
        events: SettlementEventLog
    ) {
        self.ownership = ownership
        self.events = events
    }

    func commit() async {
        events.values.append("package.commit")
    }

    func rollback() async throws {
        events.values.append("package.rollback")
        if let rollbackError { throw rollbackError }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class SettlementPersistence:
    ExtensionInstallationRecordPersisting {
    var persistError: (any Error)?
    var restoreError: (any Error)?
    private let events: SettlementEventLog

    init(events: SettlementEventLog) {
        self.events = events
    }

    func persist(record: InstalledExtension) throws {
        events.values.append("record.persist:\(record.name)")
        if let persistError { throw persistError }
    }

    func restore(
        originalRecord: InstalledExtension?,
        extensionID: String
    ) throws {
        events.values.append(
            "record.restore:\(originalRecord?.name ?? "nil")"
        )
        if let restoreError { throw restoreError }
        _ = extensionID
    }
}

@available(macOS 15.5, *)
@MainActor
private final class SettlementRuntimeRecovery:
    ExtensionInstallationPreviousRuntimeRecovering {
    private let events: SettlementEventLog

    init(events: SettlementEventLog) {
        self.events = events
    }

    func recover(
        _ previousRuntime:
            ExtensionInstallationRuntimeReplacement.PreviousRuntime,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        events.values.append("runtime.recover")
        _ = previousRuntime
        _ = mutationLease
    }
}

private final class SettlementEventLog {
    var values: [String] = []
}

private enum SettlementError: Error, Equatable {
    case injected
    case persistence
    case restoration
    case packageRollback
}
