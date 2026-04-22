import AppKit
import Foundation
@testable import Sumi
import WebKit

@available(macOS 15.5, *)
extension ExtensionManager {
    nonisolated static let webKitRuntimeBlockProgrammaticContentScriptAPIsKey =
        "debug.extensions.webkitRuntime.blockProgrammaticContentScriptAPIs.enabled"

    var loadedContextIDs: [String] {
        Array(extensionContexts.keys).sorted()
    }

    var nativeController: WKWebExtensionController? {
        extensionController
    }

    func resetInjectedBrowserConfigurationRuntimeState() {
        guard browserConfiguration !== BrowserConfiguration.shared else {
            return
        }

        tearDownExtensionRuntime(
            reason: "resetInjectedBrowserConfigurationRuntimeState",
            removeUIState: true,
            releaseController: true
        )
    }

    func orderedPinnedToolbarExtensions(
        from extensions: [InstalledExtension]
    ) -> [InstalledExtension] {
        Self.orderedPinnedToolbarExtensions(
            from: extensions,
            pinnedIDs: pinnedToolbarExtensionIDs
        )
    }

    static func orderedPinnedToolbarExtensions(
        from extensions: [InstalledExtension],
        pinnedIDs: [String]
    ) -> [InstalledExtension] {
        let enabledByID = Dictionary(
            uniqueKeysWithValues: extensions
                .filter(\.isEnabled)
                .map { ($0.id, $0) }
        )
        var seen: Set<String> = []
        let normalizedPinnedIDs = pinnedIDs.compactMap { id -> String? in
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
        return normalizedPinnedIDs.compactMap { enabledByID[$0] }
    }

    struct DebugRuntimeStateSnapshot {
        let loadedManifestIDs: [String]
        let installedPageBridgeIDs: [String]
        let externallyConnectablePolicyIDs: [String]
        let actionAnchorIDs: [String]
        let optionWindowIDs: [String]
        let nativeMessageExtensionIDs: [String]
        let pendingExternallyConnectableNativeRequestCount: Int
        let externallyConnectableNativePortIDs: [String]
        let managedPageBridgeScriptCount: Int
        let backgroundWakeInFlightIDs: [String]
        let backgroundContentLoadedIDs: [String]
        let backgroundContentFailedIDs: [String]
        let backgroundWakeTaskIDs: [String]
        let backgroundRuntimeStatesByExtensionID: [String: BackgroundRuntimeState]
        let runtimeMetricsByExtensionID: [String: ExtensionRuntimeMetrics]
        let runtimeState: ExtensionRuntimeState
        let isControllerInitialized: Bool
        let profileExtensionStoreCount: Int
        let optionalControllerIdentifier: UUID?
    }

    var debugRuntimeStateSnapshot: DebugRuntimeStateSnapshot {
        let managedPageBridgeScriptCount = browserConfiguration
            .webViewConfiguration
            .userContentController
            .userScripts
            .filter(Self.isManagedExternallyConnectablePageBridgeScript)
            .count
        let wakeStates = backgroundRuntimeStateByExtensionID
        let backgroundWakeInFlightIDs = wakeStates.compactMap { key, value in
            value == .wakeInFlight ? key : nil
        }.sorted()
        let backgroundContentLoadedIDs = wakeStates.compactMap { key, value in
            value == .loaded ? key : nil
        }.sorted()
        let backgroundContentFailedIDs = wakeStates.compactMap { key, value in
            value == .loadFailed ? key : nil
        }.sorted()

        return DebugRuntimeStateSnapshot(
            loadedManifestIDs: loadedExtensionManifests.keys.sorted(),
            installedPageBridgeIDs: installedPageBridgeIDs.sorted(),
            externallyConnectablePolicyIDs: externallyConnectablePolicies.keys.sorted(),
            actionAnchorIDs: actionAnchors.keys.sorted(),
            optionWindowIDs: optionsWindows.keys.sorted(),
            nativeMessageExtensionIDs: Array(Set(nativeMessagePortExtensionIDs.values)).sorted(),
            pendingExternallyConnectableNativeRequestCount:
                ecRegistry.allRequestIDs.count,
            externallyConnectableNativePortIDs:
                ecRegistry.allPortIDs.sorted(),
            managedPageBridgeScriptCount: managedPageBridgeScriptCount,
            backgroundWakeInFlightIDs: backgroundWakeInFlightIDs,
            backgroundContentLoadedIDs: backgroundContentLoadedIDs,
            backgroundContentFailedIDs: backgroundContentFailedIDs,
            backgroundWakeTaskIDs: backgroundWakeTasks.keys.sorted(),
            backgroundRuntimeStatesByExtensionID: wakeStates,
            runtimeMetricsByExtensionID: runtimeMetricsByExtensionID,
            runtimeState: runtimeState,
            isControllerInitialized: extensionController != nil,
            profileExtensionStoreCount: profileExtensionStores.count,
            optionalControllerIdentifier: controllerIdentifierStorage
        )
    }

    var debugCurrentProfileId: UUID? {
        currentProfileId
    }

    func debugReplaceInstalledExtensions(_ records: [InstalledExtension]) {
        installedExtensions = records.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func debugSetLoadedManifest(
        _ manifest: [String: Any],
        for extensionId: String
    ) {
        loadedExtensionManifests[extensionId] = manifest
    }

    func debugSetupExternallyConnectablePageBridge(
        extensionId: String,
        packagePath: String
    ) {
        setupExternallyConnectableBridge(
            extensionId: extensionId,
            packagePath: packagePath
        )
    }

    func debugPrepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        prepareExtensionContextForRuntime(extensionContext, extensionId: extensionId)
    }

    func debugAttachBrowserManager(_ browserManager: BrowserManager) {
        attach(browserManager: browserManager)
    }

    @discardableResult
    func debugRequestExtensionRuntime(
        reason: ExtensionRuntimeRequestReason = .extensionAction,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = true
    ) -> WKWebExtensionController? {
        requestExtensionRuntime(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions
        )
    }

    @discardableResult
    func debugRequestExtensionRuntimeAndWait(
        reason: ExtensionRuntimeRequestReason = .extensionAction,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = true
    ) async -> Bool {
        await requestExtensionRuntimeAndWait(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions
        )
    }

    nonisolated static func debugExternallyConnectableBridgeScriptSource() -> String {
        isolatedWorldExternallyConnectableBridgeScript()
    }

    nonisolated static func debugExternallyConnectableBackgroundHelperScriptSource() -> String {
        externallyConnectableBackgroundHelperScript()
    }

    @MainActor
    static func debugExternallyConnectablePageBridgeScriptSource(
        allowedHosts: [String]? = nil,
        configuredRuntimeId: String = "debug.extension",
        bridgeMarker: String = "/* debug */"
    ) -> String {
        guard let matchPattern = try? WKWebExtension.MatchPattern(
            string: "https://accounts.example.com/*"
        ) else {
            return pageWorldExternallyConnectableBridgeScript(
                configJSON: "{}",
                bridgeMarker: bridgeMarker
            )
        }

        let policy = ExternallyConnectablePolicy(
            extensionId: configuredRuntimeId,
            matchPatternStrings: ["https://accounts.example.com/*"],
            matchPatterns: [matchPattern]
        )
        let resolvedAllowedHosts = allowedHosts ?? policy.normalizedHostnames
        let config: [String: Any] = [
            "allowedHosts": resolvedAllowedHosts,
            "bridgeVersion": 1,
            "bridgeMarkerKey": bridgeMarker,
            "configuredRuntimeId": policy.extensionId,
            "debugLoggingEnabled": false,
            "nativeBridgeHandlerName": externallyConnectableNativeBridgeHandlerName,
            "supportsConnect": true,
            "transportMode": "nativeHybrid",
        ]
        let data = try? JSONSerialization.data(
            withJSONObject: config,
            options: [.sortedKeys]
        )
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return pageWorldExternallyConnectableBridgeScript(
            configJSON: json,
            bridgeMarker: bridgeMarker
        )
    }

    func debugGrantDeclaredPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]

        grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            manifest: manifest
        )
        grantRequestedMatchPatterns(
            to: extensionContext,
            webExtension: webExtension
        )
    }

    func debugAutoGrantCoveredURLs(
        _ urls: [URL],
        for extensionContext: WKWebExtensionContext
    ) -> [URL] {
        urls.filter {
            explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                $0,
                in: extensionContext
            )
        }
    }

    func debugInsertRuntimeArtifacts(for extensionId: String) {
        actionAnchors[extensionId] = []
        optionsWindows[extensionId] = NSWindow()

        let handler = NativeMessagingHandler(
            applicationId: "debug.\(extensionId)",
            browserSupportDirectory: ExtensionUtils.applicationSupportRoot(),
            appBundleURL: Bundle.main.bundleURL
        )
        let handlerID = ObjectIdentifier(handler)
        nativeMessagePortHandlers[handlerID] = handler
        nativeMessagePortExtensionIDs[handlerID] = extensionId
    }
}

@available(macOS 15.5, *)
extension ExtensionUtils {
    static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        _ = try writeJSONObjectIfChanged(object, to: url)
    }
}
