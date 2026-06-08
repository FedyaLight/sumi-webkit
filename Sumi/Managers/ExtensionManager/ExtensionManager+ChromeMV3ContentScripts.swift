import CryptoKit
import Foundation
import WebKit

#if DEBUG
    private final class ChromeMV3LivePreparedServiceWorkerLifecycleStore {
        private struct Record {
            var session: ChromeMV3ServiceWorkerSharedLifecycleSession
            var harness: ChromeMV3ServiceWorkerJSExecutionHarness?
            var profileID: String
            var extensionID: String
            var tabID: Int
            var frameID: Int
            var documentID: String
            var sessionID: String
        }

        private var records: [String: Record] = [:]

        func sessionForContentScriptRuntimePort(
            profileID: String,
            extensionID: String,
            tabID: Int,
            frameID: Int,
            documentID: String,
            urlString: String,
            manifest: ChromeMV3Manifest,
            generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
            extensionEnabled: Bool,
            localExperimentalGateAllowed: Bool,
            trace: (String) -> Void
        ) -> ChromeMV3ServiceWorkerSharedLifecycleSession? {
            let recordKey = makeRecordKey(
                profileID: profileID,
                extensionID: extensionID,
                tabID: tabID,
                frameID: frameID,
                documentID: documentID
            )
            if let existing = records[recordKey] {
                trace(
                    "[service-worker-lifecycle] extension=\(extensionID) profile=\(profileID) tab=\(tabID) frame=\(frameID) document=\(documentID) contentWorld=sumi.mv3.content.\(profileID).\(extensionID) session=\(existing.sessionID) action=reuse wakeResult=existing onConnectDispatcherCount=\(existing.session.jsListenerDispatcherCount(for: .runtimeOnConnect)) keepaliveCount=\(existing.session.runtimeOwner.snapshot.activeKeepaliveRecords.count)"
                )
                return existing.session
            }
            guard localExperimentalGateAllowed, extensionEnabled else {
                trace(
                    "[service-worker-lifecycle] extension=\(extensionID) profile=\(profileID) tab=\(tabID) frame=\(frameID) document=\(documentID) action=blocked reason=gateOrExtensionDisabled"
                )
                return nil
            }
            guard let generatedBundleRecord else {
                trace(
                    "[service-worker-lifecycle] extension=\(extensionID) profile=\(profileID) tab=\(tabID) frame=\(frameID) document=\(documentID) action=blocked reason=generatedBundleRecordMissing"
                )
                return nil
            }

            let sessionID =
                "live-normal-tab-content-script-sw-\(recordKey)"
            let key = ChromeMV3ServiceWorkerSharedLifecycleSessionKey.make(
                profileID: profileID,
                extensionID: extensionID,
                lifecycleSessionID: sessionID
            )
            let configuration =
                ChromeMV3ServiceWorkerInternalLifecycleConfiguration
                .internalFixture(
                    extensionID: key.extensionID,
                    profileID: key.profileID,
                    moduleState: .enabled,
                    explicitInternalLifecycleAllowed:
                        localExperimentalGateAllowed && extensionEnabled,
                    nativePortKeepaliveAvailableInFixture: false,
                    fixedLifecycleSessionID: key.lifecycleSessionID
                )
            let session = ChromeMV3ServiceWorkerSharedLifecycleSession(
                key: key,
                configuration: configuration
            )
            let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
                request:
                    ChromeMV3ServiceWorkerJSExecutionRequest(
                        manifest: manifest,
                        generatedBundleRecord: generatedBundleRecord,
                        extensionID: extensionID,
                        profileID: profileID,
                        moduleState: .enabled,
                        extensionEnabled: extensionEnabled,
                        localExperimentalGateAllowed:
                            localExperimentalGateAllowed,
                        dynamicImportRewriteExperimentAllowed: true
                    )
            )
            let start = harness.start()
            let canDispatch =
                start.status == .running || harness.canDispatchCapturedListeners
            if canDispatch {
                harness.attachCapturedListenerDispatchers(
                    to: session,
                    clearingExisting: true
                )
            }
            let onConnectCaptured = harness.capturedListener(
                for: .runtimeOnConnect
            )
            records[recordKey] = Record(
                session: session,
                harness: harness,
                profileID: profileID,
                extensionID: extensionID,
                tabID: tabID,
                frameID: frameID,
                documentID: documentID,
                sessionID: key.lifecycleSessionID
            )
            trace(
                "[service-worker-lifecycle] extension=\(extensionID) profile=\(profileID) tab=\(tabID) frame=\(frameID) document=\(documentID) url=\(urlString) contentWorld=sumi.mv3.content.\(profileID).\(extensionID) session=\(key.lifecycleSessionID) action=create wakeResult=\(start.status.rawValue) capturedListenerCount=\(harness.snapshot.capturedListeners.count) onConnectCaptured=\(onConnectCaptured) onConnectDispatcherCount=\(session.jsListenerDispatcherCount(for: .runtimeOnConnect)) nativePortKeepalive=false permanentBackground=false runtimeLoadable=false"
            )
            return session
        }

        func releaseContentScriptRuntimePortSession(
            profileID: String,
            extensionID: String,
            tabID: Int,
            frameID: Int,
            documentID: String,
            reason: String,
            trace: (String) -> Void
        ) {
            let recordKey = makeRecordKey(
                profileID: profileID,
                extensionID: extensionID,
                tabID: tabID,
                frameID: frameID,
                documentID: documentID
            )
            releaseRecord(
                key: recordKey,
                reason: reason,
                teardownReason: "port-close",
                trace: trace
            )
        }

        func tearDownTab(
            profileID: String,
            tabID: Int,
            documentID: String,
            reason: String,
            trace: (String) -> Void
        ) {
            for key in records.keys.sorted() {
                guard let record = records[key],
                      record.profileID == profileID,
                      record.tabID == tabID,
                      record.documentID == documentID
                else { continue }
                releaseRecord(
                    key: key,
                    reason: reason,
                    teardownReason: "tab-document-teardown",
                    trace: trace
                )
            }
        }

        func tearDownExtension(
            extensionID: String,
            reason: String,
            trace: (String) -> Void
        ) {
            for key in records.keys.sorted() {
                guard records[key]?.extensionID == extensionID else {
                    continue
                }
                releaseRecord(
                    key: key,
                    reason: reason,
                    teardownReason: "extension-teardown",
                    trace: trace
                )
            }
        }

        func reset(reason: String, trace: (String) -> Void) {
            for key in records.keys.sorted() {
                releaseRecord(
                    key: key,
                    reason: reason,
                    teardownReason: "runtime-reset",
                    trace: trace
                )
            }
        }

        private func releaseRecord(
            key: String,
            reason: String,
            teardownReason: String,
            trace: (String) -> Void
        ) {
            guard let record = records.removeValue(forKey: key) else {
                return
            }
            let activeBefore =
                record.session.runtimeOwner.snapshot.activeKeepaliveRecords
                    .count
            _ = record.session.triggerIdleRelease(reason: reason)
            let activeAfter =
                record.session.runtimeOwner.snapshot.activeKeepaliveRecords
                    .count
            record.harness?.reset()
            record.session.reset()
            trace(
                "[service-worker-lifecycle] extension=\(record.extensionID) profile=\(record.profileID) tab=\(record.tabID) frame=\(record.frameID) document=\(record.documentID) session=\(record.sessionID) action=release teardown=\(teardownReason) keepaliveBefore=\(activeBefore) keepaliveAfter=\(activeAfter) result=complete reason=\(reason)"
            )
        }

        private func makeRecordKey(
            profileID: String,
            extensionID: String,
            tabID: Int,
            frameID: Int,
            documentID: String
        ) -> String {
            stableIDLivePreparedContentScriptLifecycle(
                prefix: "content-script-sw-session",
                parts: [
                    profileID,
                    extensionID,
                    String(tabID),
                    String(frameID),
                    documentID,
                ]
            )
        }
    }

    private func stableIDLivePreparedContentScriptLifecycle(
        prefix: String,
        parts: [String]
    ) -> String {
        let joined = parts.joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(String(hex.prefix(16)))"
    }

    @available(macOS 15.5, *)
    @MainActor
    final class ChromeMV3LivePreparedContentScriptRuntime {
        private struct TabState {
            var profileID: String
            var localTabID: Int
            var documentID: String
            var navigationSequence: Int
            var urlString: String
            var webViewIdentifier: ObjectIdentifier
            var webView: WKWebView?
            var handlesByExtensionID:
                [String: ChromeMV3ContentScriptWKAttachmentHandle]
        }

        let endpointRegistry = ChromeMV3ContentScriptEndpointRegistry()
        private let serviceWorkerLifecycleStore =
            ChromeMV3LivePreparedServiceWorkerLifecycleStore()

        private var tabStates: [UUID: TabState] = [:]
        private var localTabIDs: [UUID: Int] = [:]
        private var nextNavigationSequenceByTabID: [UUID: Int] = [:]
        private var nextLocalTabID = 1

        var activeAttachmentCount: Int {
            tabStates.values.reduce(0) {
                $0 + $1.handlesByExtensionID.count
            }
        }

        func bindPreparedPackages(
            tab: Tab,
            webView: WKWebView,
            url: URL,
            installedExtensions: [InstalledExtension],
            currentProfileID: UUID?,
            browserManager: BrowserManager?,
            managerStoreRootURL: URL,
            localExperimentalGateAllowed: Bool,
            trace: @escaping (String) -> Void
        ) {
            tearDownTab(
                tab.id,
                reason: "normal-tab eligibility refresh before attachment",
                trace: trace
            )

            guard localExperimentalGateAllowed else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=localExperimentalGateClosed")
                return
            }
            guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=notNormalTabConfiguration")
                return
            }
            guard tab.existingWebView === webView else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=webViewOwnershipMismatch")
                return
            }
            guard let profile = tab.resolveProfile(),
                  profile.isEphemeral == false,
                  currentProfileID == profile.id
            else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=profileOrPrivateMismatch")
                return
            }
            guard let windowID = tab.primaryWindowId,
                  browserManager?.windowRegistry?.windows[windowID] != nil
            else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=windowMismatch")
                return
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else {
                trace("[content-script-bind] blocked tab=\(tab.id.uuidString) because=unsupportedURLScheme url=\(url.absoluteString)")
                return
            }

            let profileID = profile.id.uuidString
            let localTabID = localTabID(for: tab.id)
            let navigationSequence =
                (nextNavigationSequenceByTabID[tab.id] ?? 0) + 1
            nextNavigationSequenceByTabID[tab.id] = navigationSequence
            let documentID =
                "normal-tab-\(tab.id.uuidString)-document-\(navigationSequence)"
            let frameTarget = ChromeMV3ContentScriptFrameTarget.make(
                tabID: localTabID,
                frameID: 0,
                parentFrameID: nil,
                documentID: documentID,
                navigationSequence: navigationSequence,
                urlString: url.absoluteString,
                parentURLString: nil,
                isMainFrame: true
            )
            var handlesByExtensionID:
                [String: ChromeMV3ContentScriptWKAttachmentHandle] = [:]

            for installedExtension in installedExtensions
                where installedExtension.isEnabled
                    && installedExtension.hasContentScripts
            {
                let rootURL = URL(
                    fileURLWithPath: installedExtension.packagePath,
                    isDirectory: true
                ).standardizedFileURL
                let preparedInspection =
                    ChromeMV3PreparedContentScriptBundleInspection.inspect(
                        rootURL: rootURL
                    )
                let generatedBundleRecord =
                    preparedInspection.generatedBundleRecord
                guard preparedInspection.preparedGeneratedBundle else {
                    trace(
                        "[content-script-bind] extension=\(installedExtension.id) tab=\(localTabID) prepared=false diagnostics=\(preparedInspection.diagnostics.joined(separator: " | "))"
                    )
                    continue
                }
                let manifest: ChromeMV3Manifest
                do {
                    manifest = try ChromeMV3ManifestValidator
                        .validateManifestFile(
                            at: rootURL.appendingPathComponent("manifest.json")
                        )
                } catch {
                    trace(
                        "[content-script-bind] extension=\(installedExtension.id) tab=\(localTabID) manifest=false error=\(error.localizedDescription)"
                    )
                    continue
                }
                let permissionBroker = permissionBroker(
                    manifest: manifest,
                    extensionID: installedExtension.id,
                    profileID: profileID,
                    managerStoreRootURL: managerStoreRootURL
                )
                let plan = ChromeMV3ContentScriptAttachmentPlan.make(
                    manifest: manifest,
                    generatedBundleRootURL: rootURL,
                    extensionID: installedExtension.id,
                    profileID: profileID
                )
                let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
                    .evaluate(
                        input: ChromeMV3NormalTabContentScriptPreflightInput(
                            moduleEnabled: true,
                            extensionEnabled: installedExtension.isEnabled,
                            productRuntimePreflightAllowsNormalTabAttachment:
                                true,
                            contentScriptGate: .developerPreviewAllowed(),
                            attachmentPlan: plan,
                            permissionBroker: permissionBroker,
                            tabID: localTabID,
                            frameID: 0,
                            documentID: documentID,
                            navigationSequence: navigationSequence,
                            urlString: url.absoluteString,
                            frameTarget: frameTarget,
                            tabSurface: .normalTab,
                            generatedBundleActive: true,
                            webKitUserContentControllerAvailable: true,
                            teardownPending: false
                        )
                    )
                let attachment =
                    ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                        configuration: webView.configuration,
                        preflight: preflight,
                        permissionBroker: permissionBroker,
                        endpointRegistry: endpointRegistry,
                        sharedLifecycleSessionProvider: {
                            [serviceWorkerLifecycleStore] in
                            serviceWorkerLifecycleStore
                                .sessionForContentScriptRuntimePort(
                                    profileID: profileID,
                                    extensionID: installedExtension.id,
                                    tabID: localTabID,
                                    frameID: 0,
                                    documentID: documentID,
                                    urlString: url.absoluteString,
                                    manifest: manifest,
                                    generatedBundleRecord:
                                        generatedBundleRecord,
                                    extensionEnabled:
                                        installedExtension.isEnabled,
                                    localExperimentalGateAllowed:
                                        localExperimentalGateAllowed,
                                    trace: trace
                                )
                        },
                        sharedLifecycleSessionReleaseHandler: {
                            [serviceWorkerLifecycleStore] _, reason in
                            serviceWorkerLifecycleStore
                                .releaseContentScriptRuntimePortSession(
                                    profileID: profileID,
                                    extensionID: installedExtension.id,
                                    tabID: localTabID,
                                    frameID: 0,
                                    documentID: documentID,
                                    reason: reason,
                                    trace: trace
                                )
                        }
                    )
                attachment.handle?.bindWebViewForMessageDispatch(webView)
                if let handle = attachment.handle, attachment.result.attached {
                    handlesByExtensionID[installedExtension.id] = handle
                }
                let compatibilityReason =
                    attachment.result.attached
                        ? "declaredContentScriptMatched"
                        : (
                            attachment.result.blockers.isEmpty
                                ? "contentScriptAttachmentBlocked"
                                : attachment.result.blockers
                                    .map(\.rawValue)
                                    .joined(separator: ",")
                        )
                trace(
                    ChromeMV3CompatibilityPolicyLog.activationLine(
                        activation: "contentScriptAttach",
                        selectedPopupPath: "none",
                        compatibilityPolicy:
                            attachment.result.attached
                                ? ChromeMV3CompatibilityPolicyState.allowed
                                    .rawValue
                                : ChromeMV3CompatibilityPolicyState.blocked
                                    .rawValue,
                        reason: compatibilityReason,
                        extensionIDHash:
                            ChromeMV3CompatibilityPolicyLog.hashID(
                                installedExtension.id
                            ),
                        profileIDHash:
                            ChromeMV3CompatibilityPolicyLog.hashID(
                                profileID
                            ),
                        actionDefaultPopupPresent:
                            installedExtension.defaultPopupPath != nil,
                        serviceWorkerWakeReason:
                            "contentScriptRuntimeMessageOrPortOnDemand",
                        contentScriptAttachReason:
                            attachment.result.attached
                                ? "declaredContentScriptMatched"
                                : "blocked"
                    )
                )
                let preparedScriptPaths = preflight.matchedScripts
                    .flatMap(\.validatedJSFilePaths)
                    .joined(separator: ",")
                trace(
                    "[content-script-bind] extension=\(installedExtension.id) tab=\(localTabID) frame=0 document=\(documentID) url=\(url.absoluteString) matched=\(preflight.matchedScripts.count) preparedScripts=\(preparedScriptPaths) contentWorld=sumi.mv3.content.\(profileID).\(installedExtension.id) injectionTiming=shim:document_start,declared:manifest_run_at serviceWorkerLifecycle=lazy-content-script-runtime-port endpoint=\(attachment.result.endpointID ?? "none") attached=\(attachment.result.attached) listenerCount=\(endpointRegistry.summary.messageListenerEndpointCount) blockers=\(attachment.result.blockers.map(\.rawValue).joined(separator: ","))"
                )
            }

            guard handlesByExtensionID.isEmpty == false else {
                trace(
                    "[content-script-bind] tab=\(localTabID) endpointBindingResult=noEligiblePreparedPackageAttachment"
                )
                return
            }
            tabStates[tab.id] = TabState(
                profileID: profileID,
                localTabID: localTabID,
                documentID: documentID,
                navigationSequence: navigationSequence,
                urlString: url.absoluteString,
                webViewIdentifier: ObjectIdentifier(webView),
                webView: webView,
                handlesByExtensionID: handlesByExtensionID
            )
            traceSummary(reason: "attachment complete", trace: trace)
        }

        func noteLifecycle(
            tab: Tab,
            webView: WKWebView?,
            url: URL?,
            entrypoint: ChromeMV3ContentScriptLifecycleEntrypoint,
            trace: (String) -> Void
        ) {
            switch entrypoint {
            case .initialPageLoadEligibility, .urlHubActionClickScriptingTarget:
                break
            case .navigationStarted:
                guard let state = tabStates[tab.id] else { return }
                guard webView.map(ObjectIdentifier.init)
                    == state.webViewIdentifier,
                    (url ?? webView?.url)?.absoluteString == state.urlString
                else {
                    tearDownTab(
                        tab.id,
                        reason: "navigation started without matching prepared attachment refresh",
                        trace: trace
                    )
                    return
                }
                trace(
                    "[content-script-lifecycle] entrypoint=navigationStarted tab=\(state.localTabID) document=\(state.documentID) navigation=\(state.navigationSequence)"
                )
            case .navigationCommitted:
                guard let state = tabStates[tab.id] else { return }
                endpointRegistry.navigationCommitted(
                    profileID: state.profileID,
                    tabID: state.localTabID,
                    navigationSequence: state.navigationSequence
                )
                traceSummary(reason: "navigation committed", trace: trace)
            case .navigationFinished:
                guard tabStates[tab.id] != nil else { return }
                traceSummary(reason: "navigation finished", trace: trace)
            case .sameDocumentNavigation:
                guard let state = tabStates[tab.id] else { return }
                endpointRegistry.sameDocumentNavigation(
                    profileID: state.profileID,
                    tabID: state.localTabID,
                    navigationSequence: state.navigationSequence
                )
                traceSummary(reason: "same-document navigation", trace: trace)
            case .navigationFailed:
                tearDownTab(
                    tab.id,
                    reason: "navigation failed",
                    trace: trace
                )
            case .tabClosed:
                tearDownTab(
                    tab.id,
                    reason: "tab closed",
                    trace: trace
                )
                localTabIDs.removeValue(forKey: tab.id)
                nextNavigationSequenceByTabID.removeValue(forKey: tab.id)
            case .webViewDiscarded:
                tearDownTab(
                    tab.id,
                    reason: "web view discarded",
                    trace: trace
                )
            case .webViewReplaced:
                tearDownTab(
                    tab.id,
                    reason: "web view replaced",
                    trace: trace
                )
            case .webViewSuspended:
                tearDownTab(
                    tab.id,
                    reason: "web view suspended",
                    trace: trace
                )
            }
        }

        func tearDownExtension(
            _ extensionID: String,
            reason: String,
            trace: (String) -> Void
        ) {
            for tabID in Array(tabStates.keys) {
                guard var state = tabStates[tabID],
                      let handle =
                        state.handlesByExtensionID.removeValue(
                            forKey: extensionID
                        )
                else { continue }
                endpointRegistry.detachForExtensionDisable(
                    extensionID: extensionID,
                    profileID: state.profileID
                )
                handle.tearDown(reason: reason)
                if state.handlesByExtensionID.isEmpty {
                    tabStates.removeValue(forKey: tabID)
                } else {
                    tabStates[tabID] = state
                }
            }
            serviceWorkerLifecycleStore.tearDownExtension(
                extensionID: extensionID,
                reason: reason,
                trace: trace
            )
            traceSummary(reason: reason, trace: trace)
        }

        func tearDownAll(
            reason: String,
            trace: (String) -> Void
        ) {
            endpointRegistry.tearDownAll(reason: reason)
            for state in tabStates.values {
                for handle in state.handlesByExtensionID.values {
                    handle.tearDown(reason: reason)
                }
            }
            serviceWorkerLifecycleStore.reset(reason: reason, trace: trace)
            tabStates.removeAll()
            traceSummary(reason: reason, trace: trace)
        }

        private func tearDownTab(
            _ tabID: UUID,
            reason: String,
            trace: (String) -> Void
        ) {
            guard let state = tabStates.removeValue(forKey: tabID) else {
                return
            }
            endpointRegistry.detachForTabClose(
                profileID: state.profileID,
                tabID: state.localTabID
            )
            for handle in state.handlesByExtensionID.values {
                handle.tearDown(reason: reason)
            }
            serviceWorkerLifecycleStore.tearDownTab(
                profileID: state.profileID,
                tabID: state.localTabID,
                documentID: state.documentID,
                reason: reason,
                trace: trace
            )
            trace(
                "[content-script-teardown] tab=\(state.localTabID) document=\(state.documentID) navigation=\(state.navigationSequence) result=complete reason=\(reason)"
            )
        }

        private func localTabID(for tabID: UUID) -> Int {
            if let existing = localTabIDs[tabID] {
                return existing
            }
            let created = nextLocalTabID
            nextLocalTabID += 1
            localTabIDs[tabID] = created
            return created
        }

        private func permissionBroker(
            manifest: ChromeMV3Manifest,
            extensionID: String,
            profileID: String,
            managerStoreRootURL: URL
        ) -> ChromeMV3PermissionBroker {
            let declaredContentScriptHosts =
                manifest.contentScripts.flatMap(\.matches)
            if let record = ChromeMV3DeveloperPreviewPermissionStateStore(
                rootURL: managerStoreRootURL
            ).loadRecord(profileID: profileID, extensionID: extensionID) {
                let persisted = ChromeMV3PermissionRuntimeStateOwner(
                    snapshot: record.permissionRuntimeSnapshot
                ).permissionBroker.state
                return ChromeMV3PermissionBroker(
                    state: ChromeMV3PermissionBrokerState(
                        extensionID: extensionID,
                        profileID: profileID,
                        requiredPermissions: persisted.requiredPermissions,
                        optionalPermissions: persisted.optionalPermissions,
                        grantedOptionalPermissions:
                            persisted.grantedOptionalPermissions,
                        hostPermissions:
                            persisted.hostPermissions
                                + declaredContentScriptHosts,
                        optionalHostPermissions:
                            persisted.optionalHostPermissions,
                        grantedOptionalHostPermissions:
                            persisted.grantedOptionalHostPermissions,
                        deniedPermissions: persisted.deniedPermissions,
                        revokedPermissions: persisted.revokedPermissions,
                        unavailablePermissions:
                            persisted.unavailablePermissions,
                        unsupportedPermissions:
                            persisted.unsupportedPermissions,
                        activeTabGrants: persisted.activeTabGrants,
                        diagnostics:
                            persisted.diagnostics
                                + [
                                    "Live normal-tab binder loaded persisted developer-preview permission state.",
                                    "Manifest content_scripts.matches contributes static injection host scope.",
                                ]
                    )
                )
            }
            return ChromeMV3PermissionBroker(
                state: ChromeMV3PermissionBrokerState(
                    extensionID: extensionID,
                    profileID: profileID,
                    requiredPermissions: manifest.permissions,
                    optionalPermissions: manifest.optionalPermissions,
                    hostPermissions:
                        manifest.hostPermissions + declaredContentScriptHosts,
                    optionalHostPermissions: manifest.optionalHostPermissions,
                    diagnostics: [
                        "Live normal-tab binder uses manifest host permissions, static content_scripts.matches scope, and explicit activeTab grants only.",
                    ]
                )
            )
        }

        func scriptingExecuteScriptTarget(
            extensionID: String,
            profileID: String,
            tabID: Int,
            frameID: Int = 0
        ) -> ChromeMV3ScriptingExecuteScriptWebViewTarget? {
            guard frameID == 0 else { return nil }
            guard let state = tabStates.values.first(where: {
                $0.profileID == profileID
                    && $0.localTabID == tabID
            }) else { return nil }
            let contentWorldName =
                "sumi.mv3.content.\(profileID).\(extensionID)"
            return ChromeMV3ScriptingExecuteScriptWebViewTarget(
                webView: state.webView,
                contentWorld: WKContentWorld.world(name: contentWorldName),
                contentWorldName: contentWorldName,
                frameID: 0,
                localTabID: state.localTabID
            )
        }

        func localTabIDIfBound(tabID: UUID) -> Int? {
            tabStates[tabID]?.localTabID
        }

        @discardableResult
        func bindScriptingExecuteScriptWebViewTargetIfAllowed(
            tab: Tab,
            webView: WKWebView,
            url: URL,
            currentProfileID: UUID?,
            browserManager: BrowserManager?,
            localExperimentalGateAllowed: Bool,
            trace: @escaping (String) -> Void
        ) -> Int? {
            guard localExperimentalGateAllowed else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=localExperimentalGateClosed entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }
            guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=notNormalTabConfiguration entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }
            guard tab.existingWebView === webView else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=webViewOwnershipMismatch entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }
            guard let profile = tab.resolveProfile(),
                  profile.isEphemeral == false,
                  currentProfileID == profile.id
            else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=profileOrPrivateMismatch entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }
            guard let windowID = tab.primaryWindowId,
                  browserManager?.windowRegistry?.windows[windowID] != nil
            else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=windowMismatch entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else {
                trace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=unsupportedURLScheme url=\(url.absoluteString) entrypoint=urlHubActionClickScriptingTarget"
                )
                return nil
            }

            let profileID = profile.id.uuidString
            let localTabID = localTabID(for: tab.id)
            if var existing = tabStates[tab.id] {
                existing.webView = webView
                existing.webViewIdentifier = ObjectIdentifier(webView)
                existing.urlString = url.absoluteString
                tabStates[tab.id] = existing
                trace(
                    "[content-script-bind] entrypoint=urlHubActionClickScriptingTarget tab=\(localTabID) frame=0 url=\(url.absoluteString) endpointBindingResult=scriptingExecuteScriptTargetRefreshed contentScriptAttachments=\(existing.handlesByExtensionID.count)"
                )
                return localTabID
            }

            let navigationSequence =
                (nextNavigationSequenceByTabID[tab.id] ?? 0) + 1
            nextNavigationSequenceByTabID[tab.id] = navigationSequence
            let documentID =
                "normal-tab-\(tab.id.uuidString)-document-\(navigationSequence)"
            tabStates[tab.id] = TabState(
                profileID: profileID,
                localTabID: localTabID,
                documentID: documentID,
                navigationSequence: navigationSequence,
                urlString: url.absoluteString,
                webViewIdentifier: ObjectIdentifier(webView),
                webView: webView,
                handlesByExtensionID: [:]
            )
            trace(
                "[content-script-bind] entrypoint=urlHubActionClickScriptingTarget tab=\(localTabID) frame=0 document=\(documentID) url=\(url.absoluteString) endpointBindingResult=scriptingExecuteScriptTargetOnly contentScriptAttachments=0"
            )
            return localTabID
        }

        private func traceSummary(
            reason: String,
            trace: (String) -> Void
        ) {
            let summary = endpointRegistry.summary
            trace(
                "[content-script-summary] reason=\(reason) activeAttachments=\(activeAttachmentCount) endpoints=\(summary.activeEndpointCount) dispatchers=\(summary.activeJSDispatcherCount) listenerRegistrations=\(summary.messageListenerEndpointCount) teardownStates=\(summary.lifecycleStates.map(\.rawValue).joined(separator: ","))"
            )
        }
    }

    private enum ChromeMV3PreparedContentScriptBundleInspection {
        struct Result {
            var preparedGeneratedBundle: Bool
            var generatedBundleRecord: ChromeMV3GeneratedBundleRecord?
            var diagnostics: [String]
        }

        static func inspect(rootURL: URL) -> Result {
            let root = rootURL.standardizedFileURL
            let metadataURL = root.appendingPathComponent(
                ChromeMV3GeneratedBundleWriter.metadataFileName
            )
            let manifestURL = root.appendingPathComponent("manifest.json")
            let fileManager = FileManager.default
            guard regularFile(metadataURL, fileManager: fileManager),
                  regularFile(manifestURL, fileManager: fileManager),
                  let data = try? Data(contentsOf: metadataURL)
            else {
                return Result(
                    preparedGeneratedBundle: false,
                    generatedBundleRecord: nil,
                    diagnostics: [
                        "Prepared generated bundle metadata or manifest is missing, non-regular, or symbolic-link backed.",
                    ]
                )
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let record = try? decoder.decode(
                ChromeMV3GeneratedBundleRecord.self,
                from: data
            ) else {
                return Result(
                    preparedGeneratedBundle: false,
                    generatedBundleRecord: nil,
                    diagnostics: [
                        "Prepared generated bundle metadata could not be decoded.",
                    ]
                )
            }
            guard URL(
                fileURLWithPath: record.generatedBundleRootPath,
                isDirectory: true
            ).standardizedFileURL == root,
                URL(fileURLWithPath: record.generatedManifestPath)
                    .standardizedFileURL == manifestURL.standardizedFileURL,
                URL(fileURLWithPath: record.generatedMetadataPath)
                    .standardizedFileURL == metadataURL.standardizedFileURL
            else {
                return Result(
                    preparedGeneratedBundle: false,
                    generatedBundleRecord: nil,
                    diagnostics: [
                        "Prepared generated bundle metadata paths do not match the active generated root.",
                    ]
                )
            }
            return Result(
                preparedGeneratedBundle: true,
                generatedBundleRecord: record,
                diagnostics: [
                    "Prepared generated bundle metadata and manifest validated.",
                ]
            )
        }

        private static func regularFile(
            _ url: URL,
            fileManager: FileManager
        ) -> Bool {
            guard fileManager.fileExists(atPath: url.path),
                  (try? fileManager.destinationOfSymbolicLink(
                    atPath: url.path
                  )) == nil,
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                  )
            else { return false }
            return values.isRegularFile == true
        }
    }
#endif

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func noteChromeMV3ContentScriptLifecycleEntrypoint(
        tab: Tab,
        webView: WKWebView?,
        url: URL?,
        entrypoint: ChromeMV3ContentScriptLifecycleEntrypoint,
        localExperimentalGateAllowed: Bool = false,
        reason: String
    ) {
        let profileID = tab.resolveProfile()?.id.uuidString ?? "unknown-profile"
        let surface: ChromeMV3WebViewSurface =
            webView?.configuration.sumiIsNormalTabWebViewConfiguration == true
                ? .normalTab
                : .helperWebView
        extensionRuntimeTrace(
            "[content-script-lifecycle] entrypoint=\(entrypoint.rawValue) tab=\(tab.id.uuidString) profile=\(profileID) url=\((url ?? webView?.url)?.absoluteString ?? "nil") surface=\(surface.rawValue) normalTabConfig=\(webView?.configuration.sumiIsNormalTabWebViewConfiguration == true) developerPreviewOnly=true extensionScoped=true explicitProfileTabGateRequired=true localGate=\(localExperimentalGateAllowed) noGlobalRuntime=true reason=\(reason)"
        )

        #if DEBUG
            let trace: (String) -> Void = { [weak self] message in
                self?.extensionRuntimeTrace(message)
            }
            if entrypoint == .initialPageLoadEligibility {
                guard localExperimentalGateAllowed,
                      let webView,
                      let url,
                      canCreateChromeMV3LivePreparedContentScriptRuntime(
                        tab: tab,
                        webView: webView,
                        url: url
                      )
                else {
                    chromeMV3LivePreparedContentScriptRuntime?.noteLifecycle(
                        tab: tab,
                        webView: webView,
                        url: url,
                        entrypoint: .webViewDiscarded,
                        trace: trace
                    )
                    return
                }
                let runtime =
                    chromeMV3LivePreparedContentScriptRuntime
                    ?? ChromeMV3LivePreparedContentScriptRuntime()
                chromeMV3LivePreparedContentScriptRuntime = runtime
                runtime.bindPreparedPackages(
                    tab: tab,
                    webView: webView,
                    url: url,
                    installedExtensions: installedExtensions,
                    currentProfileID: currentProfileId,
                    browserManager: browserManager,
                    managerStoreRootURL:
                        ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
                    localExperimentalGateAllowed:
                        localExperimentalGateAllowed,
                    trace: trace
                )
                return
            }
            if entrypoint == .urlHubActionClickScriptingTarget {
                guard localExperimentalGateAllowed,
                      let webView,
                      let url,
                      canCreateChromeMV3LivePreparedContentScriptRuntime(
                        tab: tab,
                        webView: webView,
                        url: url
                      )
                else {
                    extensionRuntimeTrace(
                        "[content-script-bind] blocked tab=\(tab.id.uuidString) entrypoint=urlHubActionClickScriptingTarget reason=\(reason)"
                    )
                    return
                }
                let runtime =
                    chromeMV3LivePreparedContentScriptRuntime
                    ?? ChromeMV3LivePreparedContentScriptRuntime()
                chromeMV3LivePreparedContentScriptRuntime = runtime
                runtime.bindPreparedPackages(
                    tab: tab,
                    webView: webView,
                    url: url,
                    installedExtensions: installedExtensions,
                    currentProfileID: currentProfileId,
                    browserManager: browserManager,
                    managerStoreRootURL:
                        ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
                    localExperimentalGateAllowed:
                        localExperimentalGateAllowed,
                    trace: trace
                )
                runtime.bindScriptingExecuteScriptWebViewTargetIfAllowed(
                    tab: tab,
                    webView: webView,
                    url: url,
                    currentProfileID: currentProfileId,
                    browserManager: browserManager,
                    localExperimentalGateAllowed:
                        localExperimentalGateAllowed,
                    trace: trace
                )
                return
            }
            chromeMV3LivePreparedContentScriptRuntime?.noteLifecycle(
                tab: tab,
                webView: webView,
                url: url,
                entrypoint: entrypoint,
                trace: trace
            )
        #endif
    }

    #if DEBUG
        func chromeMV3ContentScriptEndpointRegistryIfLoaded()
            -> ChromeMV3ContentScriptEndpointRegistry?
        {
            chromeMV3LivePreparedContentScriptRuntime?.endpointRegistry
        }

        func chromeMV3ScriptingExecuteScriptTargetIfLoaded(
            extensionID: String,
            profileID: String,
            tabID: Int,
            frameID: Int = 0
        ) -> ChromeMV3ScriptingExecuteScriptWebViewTarget? {
            chromeMV3LivePreparedContentScriptRuntime?
                .scriptingExecuteScriptTarget(
                    extensionID: extensionID,
                    profileID: profileID,
                    tabID: tabID,
                    frameID: frameID
                )
        }

        func chromeMV3ScriptingExecuteScriptLocalTabIDIfLoaded(
            for tabID: UUID
        ) -> Int? {
            chromeMV3LivePreparedContentScriptRuntime?
                .localTabIDIfBound(tabID: tabID)
        }

        func bindChromeMV3ScriptingExecuteScriptTargetForURLHubActionClickIfAllowed(
            currentTab: Tab,
            localExperimentalGateAllowed: Bool
        ) -> (localTabID: Int, url: URL)? {
            guard let webView = materializedNormalTabWebView(for: currentTab),
                  let url = webView.url ?? Optional(currentTab.url),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else {
                extensionRuntimeTrace(
                    "urlHubAction click scripting target bind skipped tab=\(currentTab.id.uuidString) materializedWebView=false"
                )
                return nil
            }
            noteChromeMV3ContentScriptLifecycleEntrypoint(
                tab: currentTab,
                webView: webView,
                url: url,
                entrypoint: .urlHubActionClickScriptingTarget,
                localExperimentalGateAllowed:
                    localExperimentalGateAllowed,
                reason:
                    "ExtensionManager.bindChromeMV3ScriptingExecuteScriptTargetForURLHubActionClick"
            )
            guard let localTabID =
                chromeMV3ScriptingExecuteScriptLocalTabIDIfLoaded(
                    for: currentTab.id
                )
            else {
                extensionRuntimeTrace(
                    "urlHubAction click scripting target bind failed tab=\(currentTab.id.uuidString) localTabID=nil"
                )
                return nil
            }
            extensionRuntimeTrace(
                "urlHubAction click scripting target bound tab=\(currentTab.id.uuidString) localTabID=\(localTabID) url=\(url.absoluteString)"
            )
            return (localTabID, url)
        }

        private func materializedNormalTabWebView(for tab: Tab) -> WKWebView? {
            if let webView = tab.existingWebView,
               webView.configuration.sumiIsNormalTabWebViewConfiguration
            {
                return webView
            }
            if let windowID = tab.primaryWindowId,
               let webView = browserManager?.webViewCoordinator?.getWebView(
                   for: tab.id,
                   in: windowID
               ),
               webView.configuration.sumiIsNormalTabWebViewConfiguration
            {
                return webView
            }
            return nil
        }

        func tearDownChromeMV3LivePreparedContentScripts(
            reason: String
        ) {
            chromeMV3LivePreparedContentScriptRuntime?.tearDownAll(
                reason: reason,
                trace: { [weak self] message in
                    self?.extensionRuntimeTrace(message)
                }
            )
            chromeMV3LivePreparedContentScriptRuntime = nil
        }

        func tearDownChromeMV3LivePreparedContentScripts(
            for extensionID: String,
            reason: String
        ) {
            chromeMV3LivePreparedContentScriptRuntime?.tearDownExtension(
                extensionID,
                reason: reason,
                trace: { [weak self] message in
                    self?.extensionRuntimeTrace(message)
                }
            )
        }

        private func canCreateChromeMV3LivePreparedContentScriptRuntime(
            tab: Tab,
            webView: WKWebView,
            url: URL
        ) -> Bool {
            guard webView.configuration.sumiIsNormalTabWebViewConfiguration,
                  tab.existingWebView === webView,
                  let profile = tab.resolveProfile(),
                  profile.isEphemeral == false,
                  currentProfileId == profile.id,
                  let windowID = tab.primaryWindowId,
                  browserManager?.windowRegistry?.windows[windowID] != nil,
                  ["http", "https"].contains(
                    url.scheme?.lowercased() ?? ""
                  )
            else {
                extensionRuntimeTrace(
                    "[content-script-bind] blocked tab=\(tab.id.uuidString) because=normalTabProfileWindowOrURLGate"
                )
                return false
            }
            return true
        }
    #endif
}
