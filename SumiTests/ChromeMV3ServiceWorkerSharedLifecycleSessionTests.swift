import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerSharedLifecycleSessionTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testRegistryReturnsSameSessionForSameProfileExtensionAndSeparatesOthers()
        throws
    {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let first = try XCTUnwrap(
            registry.session(profileID: "profile-a", extensionID: "extension-a")
        )
        let second = try XCTUnwrap(
            registry.session(profileID: "profile-a", extensionID: "extension-a")
        )
        let otherExtension = try XCTUnwrap(
            registry.session(profileID: "profile-a", extensionID: "extension-b")
        )
        let otherProfile = try XCTUnwrap(
            registry.session(profileID: "profile-b", extensionID: "extension-a")
        )
        let summary = registry.summary()

        XCTAssertTrue(first === second)
        XCTAssertFalse(first === otherExtension)
        XCTAssertFalse(first === otherProfile)
        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertTrue(summary.sharedLifecycleSessionAvailableInInternalFixture)
        XCTAssertFalse(summary.serviceWorkerWakeAvailableInProduct)
        XCTAssertFalse(summary.serviceWorkerPermanentBackgroundAvailable)
        XCTAssertFalse(summary.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(summary.runtimeLoadable)
    }

    func testRegistryBlocksDisabledModuleAndClosedInternalGate() {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()

        XCTAssertNil(
            registry.session(
                profileID: "profile-a",
                extensionID: "extension-a",
                moduleState: .disabled
            )
        )
        XCTAssertNil(
            registry.session(
                profileID: "profile-a",
                extensionID: "extension-a",
                explicitInternalLifecycleAllowed: false
            )
        )
        XCTAssertEqual(registry.summary().sessionCount, 0)
        XCTAssertFalse(
            registry.summary()
                .sharedLifecycleSessionAvailableInInternalFixture
        )
    }

    func testComponentAttachDetachRecordsAllCombinedHarnessComponents()
        throws
    {
        let session = try makeSession()
        let records = attachAllComponents(to: session)
        let componentKinds = Set(records.map(\.componentKind))
        let runtime = try XCTUnwrap(
            records.first { $0.componentKind == .runtimeJSHarness }
        )

        XCTAssertEqual(
            componentKinds,
            Set(ChromeMV3ServiceWorkerSharedLifecycleComponentKind.allCases)
        )
        XCTAssertTrue(
            records.allSatisfy {
                $0.attachedSessionID == session.key.lifecycleSessionID
            }
        )
        XCTAssertEqual(
            Set(session.summary.activeComponentIDs),
            Set(records.map(\.componentID))
        )
        XCTAssertTrue(
            runtime.eventSurfacesProvided.contains(.runtimeOnMessage)
        )
        XCTAssertTrue(
            runtime.keepaliveSourcesProvided.contains(.runtimePort)
        )

        XCTAssertTrue(
            session.detachComponent(
                componentID: runtime.componentID,
                reason: .extensionDisabled
            )
        )
        let detachedRuntime = try XCTUnwrap(
            session.summary.attachedComponents.first {
                $0.componentID == runtime.componentID
            }
        )
        XCTAssertTrue(detachedRuntime.detached)
        XCTAssertEqual(detachedRuntime.detachReason, .extensionDisabled)
    }

    func testEventsFromAllSyntheticSurfacesUseOneSharedQueue()
        throws
    {
        let session = try makeSession(
            profileID: "queue-profile",
            extensionID: "queue-extension"
        )
        let components = attachAllComponentsByKind(to: session)
        registerSharedListeners(on: session)

        _ = session.routeEvent(
            reason: .runtimeMessage,
            sourceComponentID: components[.runtimeJSHarness]!.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payloadSummary: "runtime.sendMessage",
            sourceContext: .extensionPage
        )
        _ = session.routeEvent(
            reason: .runtimeConnect,
            sourceComponentID: components[.runtimeJSHarness]!.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payloadSummary: "runtime.connect",
            sourceContext: .extensionPage,
            keepaliveKind: .runtimePort,
            portID: "runtime-port"
        )
        _ = session.routeEvent(
            reason: .tabsMessage,
            sourceComponentID: components[.tabsScriptingHarness]!.componentID,
            sourceComponentKind: .tabsScriptingHarness,
            payloadSummary: "tabs.sendMessage",
            sourceContext: .extensionPage
        )
        _ = session.routeEvent(
            reason: .tabsConnect,
            sourceComponentID: components[.tabsScriptingHarness]!.componentID,
            sourceComponentKind: .tabsScriptingHarness,
            payloadSummary: "tabs.connect",
            sourceContext: .extensionPage,
            keepaliveKind: .tabsPort,
            portID: "tabs-port"
        )
        _ = session.routeEvent(
            reason: .storageChanged,
            sourceComponentID: components[.storageLocalHarness]!.componentID,
            sourceComponentKind: .storageLocalHarness,
            payloadSummary: "storage.onChanged",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnAdded,
            sourceComponentID: components[.permissionsHarness]!.componentID,
            sourceComponentKind: .permissionsHarness,
            payloadSummary: "permissions.onAdded",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .nativeMessagingConnect,
            sourceComponentID:
                components[.nativeMessagingFixtureRuntime]!.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "runtime.connect" + "Native",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port"
        )
        _ = session.routeEvent(
            reason: .nativeMessagingMessage,
            sourceComponentID:
                components[.nativeMessagingFixtureRuntime]!.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "NativePort.postMessage",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .passwordManagerDetectFields,
            sourceComponentID:
                components[.passwordManagerCombinedFixture]!.componentID,
            sourceComponentKind: .passwordManagerCombinedFixture,
            payloadSummary: "passwordManager.detectFields",
            sourceContext: .contentScript
        )
        _ = session.routeEvent(
            reason: .passwordManagerFillFields,
            sourceComponentID:
                components[.passwordManagerCombinedFixture]!.componentID,
            sourceComponentKind: .passwordManagerCombinedFixture,
            payloadSummary: "passwordManager.fillFields",
            sourceContext: .contentScript
        )

        let snapshot = session.runtimeOwner.snapshot
        XCTAssertEqual(snapshot.events.count, 10)
        XCTAssertEqual(
            Set(snapshot.events.compactMap(\.sessionID)),
            Set([session.key.lifecycleSessionID])
        )
        XCTAssertTrue(snapshot.events.allSatisfy { $0.status == .dispatched })
        XCTAssertEqual(
            Set(snapshot.events.compactMap(\.sourceComponentKind)),
            Set([
                .runtimeJSHarness,
                .tabsScriptingHarness,
                .storageLocalHarness,
                .permissionsHarness,
                .nativeMessagingFixtureRuntime,
                .passwordManagerCombinedFixture,
            ])
        )
    }

    func testMissingListenerMapsToDeterministicBlockedResult() throws {
        let session = try makeSession(
            profileID: "blocked-profile",
            extensionID: "blocked-extension"
        )
        let runtime = session.attachComponent(
            kind: .runtimeJSHarness,
            componentID: "runtime-without-listener",
            eventSurfaces: [.runtimeOnMessage]
        )

        let result = session.routeEvent(
            reason: .runtimeMessage,
            sourceComponentID: runtime.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payloadSummary: "runtime.sendMessage without listener",
            sourceContext: .extensionPage
        )

        XCTAssertFalse(result.wakeAccepted)
        XCTAssertTrue(result.blocked)
        XCTAssertEqual(result.sourceComponentKind, .runtimeJSHarness)
        XCTAssertEqual(
            result.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertEqual(
            session.runtimeOwner.snapshot.events.first?.status,
            .blocked
        )
    }

    func testSharedKeepaliveIdleReleaseAndHardTimeoutBehavior() throws {
        let session = try makeSession(
            profileID: "keepalive-profile",
            extensionID: "keepalive-extension"
        )
        let runtime = session.attachComponent(
            kind: .runtimeJSHarness,
            componentID: "runtime-keepalive",
            eventSurfaces: [.runtimeOnConnect],
            keepaliveSources: [.runtimePort]
        )
        let native = session.attachComponent(
            kind: .nativeMessagingFixtureRuntime,
            componentID: "native-keepalive",
            eventSurfaces: [.nativePortOnMessage],
            keepaliveSources: [.nativeMessagingPort]
        )
        session.registerListener(
            event: .runtimeOnConnect,
            listenerID: "runtime-on-connect"
        )
        session.registerListener(
            event: .nativePortOnMessage,
            listenerID: "native-port-on-message"
        )

        let runtimePort = session.routeEvent(
            reason: .runtimeConnect,
            sourceComponentID: runtime.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payloadSummary: "runtime.connect",
            sourceContext: .extensionPage,
            keepaliveKind: .runtimePort,
            portID: "runtime-port-a"
        )
        _ = session.routeEvent(
            reason: .nativeMessagingConnect,
            sourceComponentID: native.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "runtime.connect" + "Native",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port-a"
        )

        let blockedByBoth = session.triggerIdleRelease()
        XCTAssertTrue(blockedByBoth.blocked)
        XCTAssertEqual(
            Set(session.runtimeOwner.snapshot.activeKeepaliveRecords.map(\.kind)),
            Set([.runtimePort, .nativeMessagingPort])
        )

        XCTAssertTrue(
            session.disconnectKeepalive(
                keepaliveID: runtimePort.keepaliveRecord?.keepaliveID,
                reason: .reset
            )
        )
        XCTAssertTrue(session.triggerIdleRelease().blocked)

        XCTAssertTrue(
            session.disconnectKeepalive(
                portID: "native-port-a",
                reason: .reset
            )
        )
        let released = session.triggerIdleRelease()
        XCTAssertTrue(released.wakeAccepted)
        XCTAssertEqual(
            session.runtimeOwner.snapshot.currentState,
            .stoppedAfterIdle
        )

        _ = session.routeEvent(
            reason: .nativeMessagingConnect,
            sourceComponentID: native.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "runtime.connect" + "Native hard-stop",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "native-port-hard-stop"
        )
        let hardStop = session.triggerHardTimeout()
        let snapshot = session.runtimeOwner.snapshot
        let summary = session.summary

        XCTAssertTrue(hardStop.wakeAccepted)
        XCTAssertTrue(hardStop.dropped)
        XCTAssertEqual(snapshot.currentState, .stoppedAfterHardTimeout)
        XCTAssertTrue(snapshot.activeKeepaliveRecords.isEmpty)
        XCTAssertTrue(
            snapshot.allKeepaliveRecords.contains {
                $0.portID == "native-port-hard-stop"
                    && $0.disconnected
                    && $0.disconnectReason == .hardTimeout
                    && $0.nativeHostTerminationRequiredOnTeardown == false
            }
        )
        XCTAssertEqual(summary.listenerRegistrySummary.totalListenerCount, 0)
        XCTAssertTrue(summary.activeComponentIDs.isEmpty)
        XCTAssertEqual(
            Set(summary.detachedComponentIDs),
            Set([runtime.componentID, native.componentID])
        )
    }

    func testExtensionDisableAndProfileCloseClearSharedRegistry() throws {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let extensionSession = try XCTUnwrap(
            registry.session(profileID: "profile-a", extensionID: "extension-a")
        )
        _ = extensionSession.attachComponent(
            kind: .runtimeJSHarness,
            componentID: "runtime-a"
        )
        _ = try XCTUnwrap(
            registry.session(profileID: "profile-a", extensionID: "extension-b")
        )
        _ = try XCTUnwrap(
            registry.session(profileID: "profile-b", extensionID: "extension-a")
        )

        registry.tearDownExtension(
            profileID: "profile-a",
            extensionID: "extension-a"
        )

        XCTAssertEqual(registry.summary().sessionCount, 2)
        XCTAssertTrue(extensionSession.summary.activeComponentIDs.isEmpty)
        XCTAssertEqual(
            extensionSession.summary.attachedComponents.first?.detachReason,
            .extensionDisabled
        )

        registry.tearDownProfile(profileID: "profile-a")
        XCTAssertEqual(registry.summary().sessionCount, 1)
        registry.reset()
        XCTAssertEqual(registry.summary().sessionCount, 0)
    }

    func testSyntheticHandlersAttachAndRouteThroughSharedSession() throws {
        let profileID = "handler-profile"
        let extensionID = "abcdefghijklmnopabcdefghijklmnop"
        let session = try makeSession(
            profileID: profileID,
            extensionID: extensionID
        )
        let hostRoot = try temporaryDirectory(named: "native-host")
        let hostName =
            ChromeMV3NativeMessagingFixtureHostBuilder
            .passwordManagerFixtureHostName
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: hostRoot,
            hostName: hostName,
            extensionID: extensionID
        )

        let runtimeHandler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                surfaceID: "runtime-surface",
                explicitInternalNativeMessagingBridgeAllowed: true,
                nativeMessagingFixtureHostRootPaths: [hostRoot.path],
                nativeMessagingPermissionState: .grantedByManifest
            ),
            sharedLifecycleSession: session
        )
        _ = runtimeHandler.handle(
            listenerRequest(
                namespace: "runtime",
                methodName: "onMessage.addListener",
                listenerID: "runtime-listener"
            )
        )
        let runtimeSend = runtimeHandler.handle(
            request(
                namespace: "runtime",
                methodName: "sendMessage",
                arguments: [.object(["type": .string("runtime")])]
            )
        )
        let nativeConnect = runtimeHandler.handle(
            request(
                namespace: "runtime",
                methodName: "connect" + "Native",
                invocationMode: .fireAndForget,
                arguments: [.string(hostName)]
            )
        )
        let nativePortID = try XCTUnwrap(
            string(object(nativeConnect.resultPayload)?["portID"])
        )
        let nativeMessage = runtimeHandler.handle(
            portRequest(
                namespace: "runtime",
                methodName: "NativePort.postMessage",
                portID: nativePortID,
                arguments: [.object(["type": .string("native")])]
            )
        )

        let tabsHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                surfaceID: "tabs-surface"
            ),
            sharedLifecycleSession: session
        )
        let tabsMessage = tabsHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                arguments: [
                    .number(1),
                    .object(["type": .string("tabs")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )

        let storageHandler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                surfaceID: "storage-surface"
            ),
            sharedLifecycleSession: session
        )
        let storageSet = storageHandler.handle(
            request(
                namespace: "storage",
                methodName: "local.set",
                arguments: [.object(["token": .string("abc")])]
            )
        )

        let permissionsHandler = ChromeMV3PermissionsJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                surfaceID: "permissions-surface"
            ),
            sharedLifecycleSession: session
        )
        let permissionsAdded = permissionsHandler.handle(
            request(
                namespace: "permissions",
                methodName: "request",
                arguments: [
                    .object([
                        "permissions": .array([.string("history")]),
                        "__sumiUserGestureModeled": .bool(true),
                        "__sumiModeledPromptResult": .string("accepted"),
                    ]),
                ]
            )
        )
        let permissionsRemoved = permissionsHandler.handle(
            request(
                namespace: "permissions",
                methodName: "remove",
                arguments: [
                    .object([
                        "permissions": .array([.string("history")]),
                    ]),
                ]
            )
        )

        XCTAssertTrue(runtimeSend.succeeded)
        XCTAssertTrue(nativeConnect.succeeded)
        XCTAssertTrue(nativeMessage.succeeded)
        XCTAssertTrue(tabsMessage.succeeded)
        XCTAssertTrue(storageSet.succeeded)
        XCTAssertTrue(permissionsAdded.succeeded)
        XCTAssertTrue(permissionsRemoved.succeeded)
        XCTAssertEqual(
            runtimeSend.serviceWorkerLifecycleWakeResult?.sessionID,
            session.key.lifecycleSessionID
        )
        XCTAssertEqual(
            runtimeSend.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .runtimeJSHarness
        )
        XCTAssertEqual(
            nativeConnect.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .nativeMessagingFixtureRuntime
        )
        XCTAssertEqual(
            nativeMessage.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .nativeMessagingFixtureRuntime
        )
        XCTAssertEqual(
            tabsMessage.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .tabsScriptingHarness
        )
        XCTAssertEqual(
            storageSet.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .storageLocalHarness
        )
        XCTAssertEqual(
            permissionsAdded.serviceWorkerLifecycleWakeResult?
                .sourceComponentKind,
            .permissionsHarness
        )
        XCTAssertEqual(
            permissionsRemoved.serviceWorkerLifecycleWakeResult?
                .sourceComponentKind,
            .permissionsHarness
        )
        XCTAssertEqual(
            Set(
                session.runtimeOwner.snapshot.events.compactMap(\.sessionID)
            ),
            Set([session.key.lifecycleSessionID])
        )
        XCTAssertTrue(
            session.summary.activeComponentIDs.contains(
                "native-messaging-fixture-runtime:runtime-surface"
            )
        )

        _ = runtimeHandler.handle(
            portRequest(
                namespace: "runtime",
                methodName: "NativePort.disconnect",
                portID: nativePortID
            )
        )
        runtimeHandler.tearDown()
        tabsHandler.tearDown()
        storageHandler.runtimeStateOwner.tearDown()
        permissionsHandler.tearDown()
    }

    func testSharedLifecycleReportWritesDeterministicJSONAndKeepsProductFlagsFalse()
        throws
    {
        let report = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionReportGenerator
                .makeReport(
                    extensionID: "report-extension",
                    profileID: "report-profile"
                )
        )
        let root = try temporaryDirectory(named: "shared-report")

        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter
                .reportFileName
        )
        XCTAssertTrue(report.passwordManagerSharedLifecycleReadyInFixture)
        XCTAssertTrue(report.nativeMessagingSessionParticipation)
        XCTAssertTrue(report.sharedLifecycleSessionAvailableInInternalFixture)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertFalse(report.serviceWorkerWakeAvailableInProduct)
        XCTAssertFalse(report.serviceWorkerPermanentBackgroundAvailable)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(
            Set(report.attachedComponents.map(\.componentKind)),
            Set(ChromeMV3ServiceWorkerSharedLifecycleComponentKind.allCases)
        )
        XCTAssertEqual(
            Set(report.sharedEventQueueResults.compactMap(\.sessionID)),
            Set([report.sessionID])
        )
        XCTAssertTrue(
            report.sharedEventQueueResults.contains {
                $0.reason == .storageChanged
                    && $0.sourceComponentKind == .storageLocalHarness
            }
        )
        XCTAssertTrue(
            report.sharedEventQueueResults.contains {
                $0.reason == .permissionsChanged
                    && $0.sourceComponentKind == .permissionsHarness
            }
        )
        XCTAssertTrue(
            report.sharedEventQueueResults.contains {
                $0.reason == .nativeMessagingConnect
                    && $0.sourceComponentKind
                        == .nativeMessagingFixtureRuntime
            }
        )
        XCTAssertTrue(
            report.sharedEventQueueResults.contains {
                $0.reason == .passwordManagerDetectFields
                    && $0.sourceComponentKind
                        == .passwordManagerCombinedFixture
            }
        )
        XCTAssertTrue(
            report.sharedListenerSummary.registeredEvents
                .contains(.runtimeOnMessage)
        )
        XCTAssertTrue(
            report.sharedListenerSummary.registeredEvents
                .contains(.passwordManagerFillFields)
        )
        XCTAssertTrue(report.idleReleaseResults.contains { $0.blocked })
        XCTAssertTrue(report.idleReleaseResults.contains { $0.wakeAccepted })
        XCTAssertTrue(
            report.hardTimeoutResults.contains {
                $0.wakeAccepted && $0.dropped
            }
        )
        XCTAssertTrue(
            report.sharedKeepaliveResults.contains {
                $0.kind == .nativeMessagingPort
                    && $0.disconnected
                    && $0.disconnectReason == .hardTimeout
            }
        )

        try ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(report.reportFileName)
        let decoded = try JSONDecoder().decode(
            ChromeMV3ServiceWorkerSharedLifecycleSessionReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testDisabledModuleBlocksSharedLifecycleSessionReportAndWritesNoFile()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }
        let root = try temporaryDirectory(named: "disabled-module")
        let reportURL = root.appendingPathComponent(
            ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter
                .reportFileName
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

        let report =
            module.chromeMV3ServiceWorkerSharedLifecycleSessionReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    private func makeSession(
        profileID: String = "profile-a",
        extensionID: String = "extension-a"
    ) throws -> ChromeMV3ServiceWorkerSharedLifecycleSession {
        try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
    }

    @discardableResult
    private func attachAllComponents(
        to session: ChromeMV3ServiceWorkerSharedLifecycleSession
    ) -> [ChromeMV3ServiceWorkerSharedLifecycleComponentRecord] {
        ChromeMV3ServiceWorkerSharedLifecycleComponentKind.allCases.map {
            kind in
            session.attachComponent(
                kind: kind,
                componentID: "component-\(kind.rawValue)",
                eventSurfaces: eventSurfaces(for: kind),
                keepaliveSources: keepaliveSources(for: kind)
            )
        }
    }

    private func attachAllComponentsByKind(
        to session: ChromeMV3ServiceWorkerSharedLifecycleSession
    ) -> [
        ChromeMV3ServiceWorkerSharedLifecycleComponentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentRecord
    ] {
        Dictionary(
            uniqueKeysWithValues: attachAllComponents(to: session)
                .map { ($0.componentKind, $0) }
        )
    }

    private func registerSharedListeners(
        on session: ChromeMV3ServiceWorkerSharedLifecycleSession
    ) {
        for event in [
            ChromeMV3ServiceWorkerSyntheticListenerEvent.runtimeOnMessage,
            .runtimeOnConnect,
            .tabsOnMessage,
            .tabsOnConnect,
            .storageOnChanged,
            .permissionsOnAdded,
            .permissionsOnRemoved,
            .nativePortOnMessage,
            .nativePortOnDisconnect,
            .actionPopupEvent,
            .alarmsOnAlarm,
            .contextMenusOnClicked,
            .webNavigationOnCommitted,
            .webNavigationOnCompleted,
            .passwordManagerDetectFields,
            .passwordManagerFillFields,
        ] {
            session.registerListener(
                event: event,
                listenerID: "listener-\(event.rawValue)"
            )
        }
    }

    private func eventSurfaces(
        for kind: ChromeMV3ServiceWorkerSharedLifecycleComponentKind
    ) -> [ChromeMV3ServiceWorkerSyntheticListenerEvent] {
        switch kind {
        case .contentScriptSyntheticEndpoint:
            return [.tabsOnMessage, .tabsOnConnect]
        case .alarmsHarness:
            return [.alarmsOnAlarm]
        case .contextMenusHarness:
            return [.contextMenusOnClicked]
        case .extensionPageHostHarness:
            return [.actionPopupEvent]
        case .nativeMessagingFixtureRuntime:
            return [.nativePortOnMessage, .nativePortOnDisconnect]
        case .passwordManagerCombinedFixture:
            return [.passwordManagerDetectFields, .passwordManagerFillFields]
        case .permissionsHarness:
            return [.permissionsOnAdded, .permissionsOnRemoved]
        case .runtimeJSHarness:
            return [.runtimeOnMessage, .runtimeOnConnect]
        case .storageLocalHarness:
            return [.storageOnChanged]
        case .tabsScriptingHarness:
            return [.tabsOnMessage, .tabsOnConnect]
        case .webNavigationHarness:
            return [
                .webNavigationOnBeforeNavigate,
                .webNavigationOnCommitted,
                .webNavigationOnCompleted,
                .webNavigationOnDOMContentLoaded,
                .webNavigationOnErrorOccurred,
                .webNavigationOnHistoryStateUpdated,
                .webNavigationOnReferenceFragmentUpdated,
            ]
        }
    }

    private func keepaliveSources(
        for kind: ChromeMV3ServiceWorkerSharedLifecycleComponentKind
    ) -> [ChromeMV3ServiceWorkerInternalKeepaliveKind] {
        switch kind {
        case .nativeMessagingFixtureRuntime:
            return [.nativeMessagingPort]
        case .passwordManagerCombinedFixture:
            return [.longRunningEvent]
        case .runtimeJSHarness:
            return [.runtimePort, .pendingResponse]
        case .tabsScriptingHarness:
            return [.tabsPort]
        case .contentScriptSyntheticEndpoint, .extensionPageHostHarness,
             .alarmsHarness, .contextMenusHarness, .permissionsHarness,
             .storageLocalHarness, .webNavigationHarness:
            return []
        }
    }

    private func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func listenerRequest(
        namespace: String,
        methodName: String,
        listenerID: String
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: [],
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func portRequest(
        namespace: String,
        methodName: String,
        portID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: portID,
            diagnostics: []
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3ServiceWorkerSharedLifecycleSessionTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func object(_ value: ChromeMV3StorageValue?)
        -> [String: ChromeMV3StorageValue]?
    {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func string(_ value: ChromeMV3StorageValue?) -> String? {
        guard case .string(let value) = value else { return nil }
        return value
    }
}
