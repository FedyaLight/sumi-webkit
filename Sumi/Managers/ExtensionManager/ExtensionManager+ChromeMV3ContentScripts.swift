import Foundation
import WebKit

#if DEBUG
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
            var handlesByExtensionID:
                [String: ChromeMV3ContentScriptWKAttachmentHandle]
        }

        let endpointRegistry = ChromeMV3ContentScriptEndpointRegistry()

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
            trace: (String) -> Void
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
                        endpointRegistry: endpointRegistry
                    )
                attachment.handle?.bindWebViewForMessageDispatch(webView)
                if let handle = attachment.handle, attachment.result.attached {
                    handlesByExtensionID[installedExtension.id] = handle
                }
                let preparedScriptPaths = preflight.matchedScripts
                    .flatMap(\.validatedJSFilePaths)
                    .joined(separator: ",")
                trace(
                    "[content-script-bind] extension=\(installedExtension.id) tab=\(localTabID) url=\(url.absoluteString) matched=\(preflight.matchedScripts.count) preparedScripts=\(preparedScriptPaths) contentWorld=sumi.mv3.content.\(profileID).\(installedExtension.id) injectionTiming=shim:document_start,declared:manifest_run_at endpoint=\(attachment.result.endpointID ?? "none") attached=\(attachment.result.attached) listenerCount=\(endpointRegistry.summary.messageListenerEndpointCount) blockers=\(attachment.result.blockers.map(\.rawValue).joined(separator: ","))"
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
            case .initialPageLoadEligibility:
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
                    diagnostics: [
                        "Prepared generated bundle metadata paths do not match the active generated root.",
                    ]
                )
            }
            return Result(
                preparedGeneratedBundle: true,
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
