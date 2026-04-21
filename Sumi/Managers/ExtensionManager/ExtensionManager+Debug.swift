#if DEBUG
//
//  ExtensionManager+Debug.swift
//  Sumi
//
//  DEBUG-only test surface kept out of the production manager core.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
private final class ExtensionManagerDebugRegistry {
    private static let lock = NSLock()
    private static var hooksByManagerID: [ObjectIdentifier: ExtensionManager.TestHooks] = [:]

    static func hooks(for managerID: ObjectIdentifier) -> ExtensionManager.TestHooks {
        lock.lock()
        defer { lock.unlock() }
        return hooksByManagerID[managerID] ?? ExtensionManager.TestHooks()
    }

    static func setHooks(
        _ hooks: ExtensionManager.TestHooks,
        for managerID: ObjectIdentifier
    ) {
        lock.lock()
        hooksByManagerID[managerID] = hooks
        lock.unlock()
    }

    static func clearHooks(for managerID: ObjectIdentifier) {
        lock.lock()
        hooksByManagerID.removeValue(forKey: managerID)
        lock.unlock()
    }
}

@available(macOS 15.5, *)
extension ExtensionManager {
    struct TestHooks {
        var beforePersistInstalledRecord: ((InstalledExtension) throws -> Void)?
        var beforeControllerLoad:
            ((String, ExtensionManager.WebExtensionStorageSnapshot) throws -> Void)?
        var backgroundContentWake:
            (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
        var webExtensionDataCleanup: (@MainActor (String) async -> Bool)?
        var didOpenTab: ((UUID) -> Void)?
        var didChangeTabProperties:
            ((UUID, WKWebExtension.TabChangedProperties) -> Void)?
    }

    struct DebugRuntimeStateSnapshot {
        let loadedManifestIDs: [String]
        let installedPageBridgeIDs: [String]
        let externallyConnectablePolicyIDs: [String]
        let actionAnchorIDs: [String]
        let optionWindowIDs: [String]
        let nativeMessageExtensionIDs: [String]
        let trackedExternallyConnectableWebViewCount: Int
        let pendingExternallyConnectableNativeRequestCount: Int
        let externallyConnectableNativePortIDs: [String]
        let managedPageBridgeScriptCount: Int
        let backgroundWakeInFlightIDs: [String]
        let backgroundContentLoadedIDs: [String]
        let backgroundContentFailedIDs: [String]
        let backgroundWakeTaskIDs: [String]
        let backgroundRuntimeStatesByExtensionID: [String: BackgroundRuntimeState]
        let runtimeMetricsByExtensionID: [String: ExtensionRuntimeMetrics]
    }

    var testHooks: TestHooks {
        get {
            ExtensionManagerDebugRegistry.hooks(for: ObjectIdentifier(self))
        }
        set {
            ExtensionManagerDebugRegistry.setHooks(
                newValue,
                for: ObjectIdentifier(self)
            )
        }
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
            trackedExternallyConnectableWebViewCount: ecRegistry.trackedPageURLWebViewCount,
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
            runtimeMetricsByExtensionID: runtimeMetricsByExtensionID
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

    nonisolated func clearDebugState() {
        ExtensionManagerDebugRegistry.clearHooks(for: ObjectIdentifier(self))
    }
}
#endif
