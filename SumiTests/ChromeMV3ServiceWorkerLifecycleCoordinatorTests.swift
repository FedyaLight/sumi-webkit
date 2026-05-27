import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerLifecycleCoordinatorTests: XCTestCase {
    func testLifecycleStateModelNeverReportsRunningNow() {
        for state in ChromeMV3ServiceWorkerLifecycleState.allCases {
            let snapshot = ChromeMV3ServiceWorkerLifecycleStateSnapshot
                .diagnostic(state: state)

            XCTAssertFalse(snapshot.workerRunningNow)
            XCTAssertFalse(snapshot.contextCreated)
            XCTAssertFalse(snapshot.workerWakeAvailableNow)
            XCTAssertFalse(snapshot.runtimeLoadable)
        }
    }

    func testRuntimeMessageWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .runtimeMessage,
            sourceContext: .contentScript,
            targetListenerSurface: .runtimeOnMessageServiceWorker,
            requiresPermissionOrActiveTab: true
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .runtimeMessage)
        XCTAssertFalse(request.canWakeNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canDispatchEventsNow)
        XCTAssertTrue(
            preflight.blockers.contains(.listenerRegistrationUnavailable)
        )
        XCTAssertTrue(preflight.blockers.contains(.contextNotLoaded))
        XCTAssertTrue(preflight.canQueuePendingEventInModel)
    }

    func testStorageChangedWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.storageChanged(
            extensionID: "extension-a",
            profileID: "profile-a",
            areaName: "local",
            changedKeys: ["token"]
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .storageChanged)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canDispatchEventsNow)
        XCTAssertEqual(
            preflight.request.targetListenerSurface,
            .serviceWorkerLifecycleEventListener
        )
    }

    func testNativeMessagingConnectWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest
            .nativeMessagingConnect(
                extensionID: "extension-a",
                profileID: "profile-a"
            )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .nativeMessagingConnect)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertTrue(preflight.blockers.contains(.nativeMessagingBlocked))
    }

    func testPendingEventQueueStoresModelEventsWithoutDispatch() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .testFixture,
            sourceContext: .unknown,
            targetListenerSurface: .serviceWorkerLifecycleEventListener
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )
        var queue = ChromeMV3ServiceWorkerPendingEventQueue.empty
        let event = queue.enqueue(
            preflight: preflight,
            payloadSummary: "test payload"
        )
        queue.markEventBlocked(eventID: event.eventID, reason: "fixture")
        queue.markEventDropped(eventID: event.eventID, reason: "fixture drop")
        let snapshot = queue.snapshot()

        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events.first?.sequence, 1)
        XCTAssertEqual(snapshot.events.first?.status, .dropped)
        XCTAssertFalse(snapshot.dispatchAttemptedNow)
    }

    func testIdleReleasePolicyIsModeledWithoutScheduling() {
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .idleRelease

        XCTAssertEqual(policy.idleAfterInactivitySeconds, 30)
        XCTAssertTrue(policy.modeledOnly)
        XCTAssertFalse(policy.schedulesDeadlineNow)
        XCTAssertFalse(policy.releasesWorkerNow)
    }

    func testHardTimeoutPolicyIsModeledWithoutScheduling() {
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .hardTimeout

        XCTAssertEqual(policy.maximumSingleRequestSeconds, 300)
        XCTAssertEqual(policy.fetchResponseLimitSeconds, 30)
        XCTAssertTrue(policy.modeledOnly)
        XCTAssertFalse(policy.schedulesDeadlineNow)
        XCTAssertFalse(policy.terminatesWorkerNow)
    }

    func testRuntimePortKeepaliveSourceIsModeledButInactive() {
        let source = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .runtimePort,
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertTrue(source.wouldKeepAliveInFuture)
        XCTAssertFalse(source.implementedNow)
        XCTAssertTrue(source.passwordManagerRelevance)
    }

    func testNativeMessagingPortKeepaliveSourceIsBlocked() {
        let source = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .nativeMessagingPort,
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .nativeMessagingPort

        XCTAssertTrue(source.wouldKeepAliveInFuture)
        XCTAssertFalse(source.implementedNow)
        XCTAssertTrue(source.blockers.contains {
            $0.contains("Native messaging keepalive is blocked")
        })
        XCTAssertTrue(policy.nativeMessagingBlocked)
        XCTAssertFalse(policy.launchesHostNow)
    }

    func testInternalLifecycleOwnerStartsStoppedAndScoped() {
        let owner = makeInternalLifecycleOwner()
        let snapshot = owner.snapshot

        XCTAssertEqual(snapshot.currentState, .stopped)
        XCTAssertNil(snapshot.currentSessionID)
        XCTAssertEqual(snapshot.extensionID, "extension-a")
        XCTAssertEqual(snapshot.profileID, "profile-a")
        XCTAssertTrue(
            snapshot.serviceWorkerLifecycleAvailableInInternalFixture
        )
        XCTAssertFalse(snapshot.serviceWorkerWakeAvailableInProduct)
        XCTAssertFalse(snapshot.serviceWorkerPermanentBackgroundAvailable)
        XCTAssertFalse(snapshot.runtimeLoadable)
    }

    func testInternalRuntimeMessageWakeDispatchesSyntheticListener() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "runtime-on-message"
        )

        let result = owner.requestWake(
            reason: .runtimeMessage,
            payload: .object(["type": .string("fixture-message")]),
            payloadSummary: "runtime message fixture",
            sourceContext: .contentScript
        )
        let snapshot = owner.snapshot

        XCTAssertTrue(result.wakeAccepted)
        XCTAssertTrue(result.queued)
        XCTAssertTrue(result.dispatched)
        XCTAssertFalse(result.blocked)
        XCTAssertEqual(result.listenerEvent, .runtimeOnMessage)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events.first?.sequence, 1)
        XCTAssertEqual(snapshot.events.first?.status, .dispatched)
        XCTAssertEqual(snapshot.dispatchedEventCount, 1)
        XCTAssertEqual(snapshot.currentState, .idleEligible)
    }

    func testInternalRuntimeMessageWakeBlockedInProductScope() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "runtime-on-message"
        )

        let result = owner.requestWake(
            reason: .runtimeMessage,
            payloadSummary: "product runtime message",
            sourceContext: .contentScript,
            scope: .product
        )

        XCTAssertFalse(result.wakeAccepted)
        XCTAssertTrue(result.blocked)
        XCTAssertEqual(result.scope, .product)
        XCTAssertTrue(
            result.blockers.contains(
                "Product service-worker wake remains unavailable."
            )
        )
        XCTAssertEqual(owner.snapshot.currentState, .blocked)
    }

    func testInternalStorageChangedWakeRequiresListener() {
        let blockedOwner = makeInternalLifecycleOwner()
        let blocked = blockedOwner.requestWake(
            reason: .storageChanged,
            listenerEvent: .storageOnChanged,
            payloadSummary: "storage change without listener",
            sourceContext: .serviceWorker
        )

        XCTAssertFalse(blocked.wakeAccepted)
        XCTAssertTrue(blocked.blocked)
        XCTAssertEqual(
            blocked.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )

        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .storageOnChanged,
            listenerID: "storage-on-changed"
        )
        let accepted = owner.requestWake(
            reason: .storageChanged,
            listenerEvent: .storageOnChanged,
            payloadSummary: "storage change with listener",
            sourceContext: .serviceWorker
        )

        XCTAssertTrue(accepted.wakeAccepted)
        XCTAssertTrue(accepted.dispatched)
        XCTAssertEqual(accepted.listenerEvent, .storageOnChanged)
    }

    func testInternalPermissionsChangedWakeRequiresListener() {
        let blockedOwner = makeInternalLifecycleOwner()
        let blocked = blockedOwner.requestWake(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnAdded,
            payloadSummary: "permissions change without listener",
            sourceContext: .serviceWorker
        )

        XCTAssertFalse(blocked.wakeAccepted)
        XCTAssertTrue(blocked.blocked)
        XCTAssertTrue(
            blocked.blockers.contains(
                "No synthetic/model listener is registered."
            )
        )

        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .permissionsOnAdded,
            listenerID: "permissions-on-added"
        )
        let accepted = owner.requestWake(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnAdded,
            payloadSummary: "permissions change with listener",
            sourceContext: .serviceWorker
        )

        XCTAssertTrue(accepted.wakeAccepted)
        XCTAssertTrue(accepted.dispatched)
        XCTAssertEqual(accepted.listenerEvent, .permissionsOnAdded)
    }

    func testInternalNativeMessagingConnectRecordsPortKeepalive() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .nativePortOnMessage,
            listenerID: "native-port-on-message"
        )

        let result = owner.requestWake(
            reason: .nativeMessagingConnect,
            listenerEvent: .nativePortOnMessage,
            payloadSummary: "native Port connect",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port-a"
        )
        let snapshot = owner.snapshot

        XCTAssertTrue(result.wakeAccepted)
        XCTAssertEqual(result.keepaliveRecord?.kind, .nativeMessagingPort)
        XCTAssertEqual(result.keepaliveRecord?.portID, "native-port-a")
        XCTAssertTrue(
            result.keepaliveRecord?.nativeHostLaunchOwnedElsewhere ?? false
        )
        XCTAssertTrue(snapshot.nativePortKeepaliveAvailableInFixture)
        XCTAssertEqual(snapshot.activeKeepaliveRecords.count, 1)
        XCTAssertEqual(snapshot.currentState, .runningInSyntheticFixture)
    }

    func testInternalEventQueueDispatchesDeterministically() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "listener-b"
        )
        owner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "listener-a"
        )

        let first = owner.requestWake(
            reason: .runtimeMessage,
            payloadSummary: "first runtime message",
            sourceContext: .contentScript
        )
        let second = owner.requestWake(
            reason: .runtimeMessage,
            payloadSummary: "second runtime message",
            sourceContext: .contentScript
        )
        let snapshot = owner.snapshot

        XCTAssertTrue(first.dispatched)
        XCTAssertTrue(second.dispatched)
        XCTAssertEqual(snapshot.events.map(\.sequence), [1, 2])
        XCTAssertEqual(snapshot.events.map(\.status), [
            .dispatched,
            .dispatched,
        ])
        XCTAssertEqual(snapshot.events.first?.dispatchedListenerID, "listener-b")
    }

    func testInternalNoListenerMapsToNoReceivingEnd() {
        let owner = makeInternalLifecycleOwner()

        let result = owner.requestWake(
            reason: .runtimeMessage,
            payloadSummary: "message without listener",
            sourceContext: .contentScript
        )
        let snapshot = owner.snapshot

        XCTAssertFalse(result.wakeAccepted)
        XCTAssertTrue(result.blocked)
        XCTAssertEqual(
            result.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertEqual(snapshot.blockedEventCount, 1)
        XCTAssertEqual(snapshot.events.first?.status, .blocked)
    }

    func testInternalIdleReleaseRequiresExplicitTriggerAndNoKeepalive() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .runtimeOnConnect,
            listenerID: "runtime-on-connect"
        )
        let port = owner.requestWake(
            reason: .runtimeConnect,
            listenerEvent: .runtimeOnConnect,
            payloadSummary: "runtime Port",
            sourceContext: .contentScript,
            keepaliveKind: .runtimePort,
            portID: "runtime-port-a"
        )

        XCTAssertEqual(owner.snapshot.currentState, .runningInSyntheticFixture)
        let deferred = owner.triggerIdleRelease()
        XCTAssertFalse(deferred.wakeAccepted)
        XCTAssertTrue(deferred.blocked)

        XCTAssertTrue(
            owner.disconnectKeepalive(
                keepaliveID: port.keepaliveRecord?.keepaliveID,
                reason: .reset
            )
        )
        XCTAssertEqual(owner.snapshot.currentState, .idleEligible)
        let released = owner.triggerIdleRelease()

        XCTAssertTrue(released.wakeAccepted)
        XCTAssertEqual(owner.snapshot.currentState, .stoppedAfterIdle)
        XCTAssertNil(owner.snapshot.currentSessionID)
    }

    func testInternalHardTimeoutStopsAndDisconnectsKeepalives() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .nativePortOnMessage,
            listenerID: "native-port-on-message"
        )
        _ = owner.requestWake(
            reason: .nativeMessagingConnect,
            listenerEvent: .nativePortOnMessage,
            payloadSummary: "native Port connect",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port-a"
        )

        let timeout = owner.triggerHardTimeout()
        let snapshot = owner.snapshot

        XCTAssertTrue(timeout.wakeAccepted)
        XCTAssertTrue(timeout.dropped)
        XCTAssertEqual(snapshot.currentState, .stoppedAfterHardTimeout)
        XCTAssertTrue(snapshot.activeKeepaliveRecords.isEmpty)
        XCTAssertTrue(
            snapshot.allKeepaliveRecords.allSatisfy {
                $0.disconnected
                    && $0.disconnectReason == .hardTimeout
                    && $0.nativeHostTerminationRequiredOnTeardown == false
            }
        )
    }

    func testInternalRuntimePortKeepaliveDefersIdleUntilDisconnect() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .runtimeOnConnect,
            listenerID: "runtime-on-connect"
        )
        let result = owner.requestWake(
            reason: .runtimeConnect,
            listenerEvent: .runtimeOnConnect,
            payloadSummary: "runtime Port",
            sourceContext: .contentScript,
            keepaliveKind: .runtimePort,
            portID: "runtime-port-a"
        )

        XCTAssertEqual(result.keepaliveRecord?.kind, .runtimePort)
        XCTAssertEqual(owner.snapshot.currentState, .runningInSyntheticFixture)
        XCTAssertFalse(owner.triggerIdleRelease().wakeAccepted)
        XCTAssertTrue(
            owner.disconnectKeepalive(
                portID: "runtime-port-a",
                reason: .reset
            )
        )
        XCTAssertEqual(owner.snapshot.currentState, .idleEligible)
    }

    func testInternalNativePortKeepaliveDisconnectClearsHostRequirement() {
        let owner = makeInternalLifecycleOwner()
        owner.registerListener(
            event: .nativePortOnMessage,
            listenerID: "native-port-on-message"
        )
        let result = owner.requestWake(
            reason: .nativeMessagingConnect,
            listenerEvent: .nativePortOnMessage,
            payloadSummary: "native Port connect",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port-a"
        )

        XCTAssertTrue(result.keepaliveRecord?.active ?? false)
        XCTAssertTrue(
            result.keepaliveRecord?.nativeHostTerminationRequiredOnTeardown
                ?? false
        )
        XCTAssertTrue(
            owner.disconnectKeepalive(
                portID: "native-port-a",
                reason: .reset
            )
        )
        let record = owner.snapshot.allKeepaliveRecords.first

        XCTAssertFalse(record?.active ?? true)
        XCTAssertTrue(record?.disconnected ?? false)
        XCTAssertFalse(
            record?.nativeHostTerminationRequiredOnTeardown ?? true
        )
    }

    func testInternalLifecycleTeardownClearsStateForDisableAndProfileClose() {
        let disabledOwner = makeInternalLifecycleOwner()
        disabledOwner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "runtime-on-message"
        )
        _ = disabledOwner.requestWake(
            reason: .runtimeMessage,
            payloadSummary: "runtime message",
            sourceContext: .contentScript
        )
        disabledOwner.tearDownForExtensionDisable()
        let disabled = disabledOwner.snapshot

        XCTAssertEqual(disabled.currentState, .stopped)
        XCTAssertTrue(disabled.events.isEmpty)
        XCTAssertTrue(disabled.activeKeepaliveRecords.isEmpty)
        XCTAssertEqual(disabled.listenerRegistrySummary.totalListenerCount, 0)

        let profileOwner = makeInternalLifecycleOwner()
        profileOwner.registerListener(
            event: .storageOnChanged,
            listenerID: "storage-on-changed"
        )
        _ = profileOwner.requestWake(
            reason: .storageChanged,
            listenerEvent: .storageOnChanged,
            payloadSummary: "storage change",
            sourceContext: .serviceWorker
        )
        profileOwner.tearDownForProfileClose()
        let profile = profileOwner.snapshot

        XCTAssertEqual(profile.currentState, .stopped)
        XCTAssertTrue(profile.events.isEmpty)
        XCTAssertEqual(profile.listenerRegistrySummary.totalListenerCount, 0)
    }

    func testPermanentBackgroundIsRejectedByCoordinatorDiagnostics() {
        let coordinator = ChromeMV3ServiceWorkerLifecycleCoordinator.blocked(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertTrue(
            coordinator.lifecycleState.permanentBackgroundForbidden
        )
        XCTAssertTrue(
            coordinator.diagnostics.contains {
                $0.kind == .permanentBackgroundRejected
            }
        )
    }

    func testListenerUnavailableAndContextNotLoadedMapToWakeBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .runtimeMessage,
            sourceContext: .contentScript,
            targetListenerSurface: .runtimeOnMessageServiceWorker
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertTrue(
            preflight.blockers.contains(.listenerRegistrationUnavailable)
        )
        XCTAssertTrue(preflight.blockers.contains(.contextNotLoaded))
        XCTAssertTrue(
            preflight.blockers.contains(.serviceWorkerWakeUnavailable)
        )
    }

    func testStorageOperationOnChangedReferencesWakePreflightButDoesNotDispatch() {
        var broker = ChromeMV3StorageBroker(
            namespace: ChromeMV3StorageNamespace(
                profileID: "profile-a",
                extensionID: "extension-a",
                area: .local
            )
        )

        let result = broker.set(["token": .string("abc")])
        let payload = result.changeSet.futureOnChangedPayload

        XCTAssertTrue(payload.serviceWorkerWakeRequired)
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertEqual(
            payload.serviceWorkerWakePreflight?.request.reason,
            .storageChanged
        )
        XCTAssertFalse(
            payload.serviceWorkerWakePreflight?.canWakeServiceWorkerNow
                ?? true
        )
    }

    func testMessagingRouteReferencesWakePreflightButDoesNotDispatch() {
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .contentScriptToServiceWorker,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 1,
            frameID: 0,
            sourceURL: "https://example.com/login"
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)
        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: .blocked
        )

        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertFalse(evaluation.canWakeServiceWorkerNow)
        XCTAssertEqual(
            evaluation.serviceWorkerWakePreflight?.request.reason,
            .runtimeMessage
        )
        XCTAssertFalse(
            evaluation.serviceWorkerWakePreflight?.canDispatchEventsNow
                ?? true
        )
    }

    func testPortLifecycleReferencesKeepalivePolicyButDoesNotOpenPort() {
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .runtimeConnect,
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)
        let contract = ChromeMV3RuntimePortContract.model(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: .blocked
        )

        XCTAssertFalse(contract.canOpenPortNow)
        XCTAssertFalse(contract.portLifecycleImplemented)
        XCTAssertEqual(contract.keepaliveSource?.kind, .runtimePort)
        XCTAssertFalse(contract.keepaliveSource?.implementedNow ?? true)
    }

    func testPermissionsEventReferencesWakePreflightButDoesNotDispatch() {
        let payload = ChromeMV3PermissionsAPIContractEvaluator.eventPayload(
            kind: .onAdded,
            source: .testFixture,
            extensionID: "extension-a",
            profileID: "profile-a",
            permissions: ["storage"],
            origins: []
        )

        XCTAssertFalse(payload.serviceWorkerWakeRequired)
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertEqual(
            payload.serviceWorkerWakePreflight?.request.reason,
            .permissionsChanged
        )
        XCTAssertFalse(
            payload.serviceWorkerWakePreflight?.canWakeServiceWorkerNow
                ?? true
        )
        XCTAssertFalse(payload.canWakeServiceWorkerNow)
    }

    func testPasswordManagerFixtureReportsInternalLifecycleReadiness() {
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "password-manager-fixture",
            profileID: "profile-a",
            serviceWorkerScriptDeclared: true,
            passwordManagerLikeFixtureDetected: true,
            storagePermissionDetected: true,
            nativeMessagingDetected: true
        )
        let password = report.passwordManagerServiceWorkerSummary

        XCTAssertTrue(password.passwordManagerServiceWorkerReady)
        XCTAssertTrue(password.passwordManagerServiceWorkerReadyInFixture)
        XCTAssertTrue(
            password.contentScriptMessageRequiresServiceWorkerWake
        )
        XCTAssertTrue(password.popupMessageRequiresServiceWorkerWake)
        XCTAssertTrue(password.storageOnChangedMayRequireServiceWorkerWake)
        XCTAssertFalse(
            password.nativeMessagingPortWouldAffectKeepaliveButBlocked
        )
        XCTAssertTrue(password.runtimePortKeepaliveImplemented)
        XCTAssertFalse(password.idleUnloadPolicyModeledButNotActive)
        XCTAssertTrue(report.passwordManagerServiceWorkerReadyInFixture)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertTrue(
            report.summary.serviceWorkerLifecycleAvailableInInternalFixture
        )
        XCTAssertFalse(report.summary.serviceWorkerWakeAvailableInProduct)
        XCTAssertFalse(
            report.summary.serviceWorkerPermanentBackgroundAvailable
        )
    }

    func testLifecycleReportKeepsRuntimeFlagsFalse() {
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canDispatchEventsNow)
        XCTAssertFalse(report.canOpenPortNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.summary.canWakeServiceWorkerNow)
        XCTAssertFalse(report.summary.canDispatchEventsNow)
        XCTAssertFalse(report.summary.canOpenPortNow)
        XCTAssertFalse(report.summary.canLoadContextNow)
        XCTAssertFalse(report.summary.runtimeLoadable)
        XCTAssertTrue(report.serviceWorkerLifecycleAvailableInInternalFixture)
        XCTAssertFalse(report.serviceWorkerWakeAvailableInProduct)
        XCTAssertFalse(report.serviceWorkerPermanentBackgroundAvailable)
        XCTAssertTrue(report.nativePortKeepaliveAvailableInFixture)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
    }

    func testLifecycleReportWriterWritesDeterministicJSON() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        try ChromeMV3ServiceWorkerLifecycleReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let reportURL = root.appendingPathComponent(
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let decoded = try JSONDecoder().decode(
            ChromeMV3ServiceWorkerLifecycleReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testDisabledModuleWritesNoServiceWorkerLifecycleReport() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reportURL = root.appendingPathComponent(
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            browserConfiguration: BrowserConfiguration()
        )

        let report = module.chromeMV3ServiceWorkerLifecycleReportIfEnabled(
            fromRewrittenBundleRoot: root,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNoForbiddenRuntimeBoundaryCallsInChromeMV3LifecycleSources()
        throws
    {
        let root = repositoryRoot()
        let targets = [
            root.appendingPathComponent("Sumi/Models/Extension/ChromeMV3"),
            root.appendingPathComponent("SumiTests"),
        ]
        let literalPatterns = [
            "WKWebExtensionContext" + "(",
            "load" + "Extension" + "Context",
            "add" + "User" + "Script",
            "connect" + "Native",
            "Pro" + "cess" + "(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ]
        let regexPatterns = [
            "runtimeLoadable.*" + "tr" + "ue",
            "serviceWorkerWakeAvailableInProduct.*" + "tr" + "ue",
            "serviceWorkerPermanentBackgroundAvailable.*" + "tr" + "ue",
            "passwordManagerProductRuntimeReady.*" + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable.*" + "tr" + "ue",
            "productRuntimeExposed.*" + "tr" + "ue",
        ]

        let swiftFiles = try targets.flatMap(swiftFiles)
            .filter {
                $0.lastPathComponent.hasPrefix("ChromeMV3")
                    || $0.path.contains("/ChromeMV3/")
            }
        let texts = try swiftFiles.map {
            ($0.path, try String(contentsOf: $0, encoding: .utf8))
        }
        let tabsScriptingHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
            )
            .path
        let storageLocalSyntheticHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
            )
            .path
        let passwordManagerSyntheticHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
            )
            .path
        let extensionEventAPIsSyntheticHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift"
            )
            .path
        let sidePanelOffscreenIdentitySyntheticHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift"
            )
            .path
        let runtimeJSMessagingHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift"
            )
            .path
        let runtimeJSMessagingHarnessTestsPath =
            root
            .appendingPathComponent(
                "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift"
            )
            .path
        let nativeMessagingInternalRuntimePath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
            )
            .path
        let nativeMessagingInternalRuntimeTestsPath =
            root
            .appendingPathComponent(
                "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift"
            )
            .path
        for pattern in literalPatterns {
            let offenders = texts
                .filter { $0.1.contains(pattern) }
                .map(\.0)
                .filter {
                    pattern == "add" + "User" + "Script"
                        ? $0 != tabsScriptingHarnessPath
                            && $0 != storageLocalSyntheticHarnessPath
                            && $0 != passwordManagerSyntheticHarnessPath
                            && $0 != extensionEventAPIsSyntheticHarnessPath
                            && $0
                                != sidePanelOffscreenIdentitySyntheticHarnessPath
                        : pattern == "connect" + "Native"
                            ? $0 != runtimeJSMessagingHarnessPath
                                && $0 != runtimeJSMessagingHarnessTestsPath
                                && $0 != passwordManagerSyntheticHarnessPath
                                && $0 != nativeMessagingInternalRuntimePath
                                && $0 != nativeMessagingInternalRuntimeTestsPath
                        : pattern == "Pro" + "cess" + "("
                            ? $0 != nativeMessagingInternalRuntimePath
                                && $0 != nativeMessagingInternalRuntimeTestsPath
                        : true
                }
            XCTAssertTrue(offenders.isEmpty, "\(pattern): \(offenders)")
        }
        for pattern in regexPatterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let offenders = texts.filter { _, text in
                regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                ) != nil
            }.map(\.0)
            XCTAssertTrue(offenders.isEmpty, "\(pattern): \(offenders)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeInternalLifecycleOwner()
        -> ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner
    {
        ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner(
            configuration: .internalFixture(
                extensionID: "extension-a",
                profileID: "profile-a",
                nativePortKeepaliveAvailableInFixture: true
            )
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift"
            else { return nil }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            return values.isRegularFile == true ? url : nil
        }
    }
}
