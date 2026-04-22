//
//  ExtensionManager.swift
//  Sumi
//
//  Safari/WebExtension runtime rebuilt on top of native WebKit APIs.
//

import AppKit
import Combine
import Foundation
import OSLog
import SwiftData
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject {
    static let logger = Logger.sumi(category: "Extensions")
    static let controllerIdentifierKey =
        "\(SumiAppIdentity.bundleIdentifier).WKWebExtensionController.Identifier"
    nonisolated static let externallyConnectableBridgeFilename = "sumi_bridge.js"
    nonisolated static let externallyConnectableBackgroundHelperFilename =
        "sumi_external_runtime.js"
    nonisolated static let externallyConnectableServiceWorkerWrapperFilename =
        "sumi_external_worker.js"
    // bitwardenIframeBridgeFilename removed (Bitwarden-specific iframe injection).
    nonisolated static let webKitRuntimeCompatibilityPreludeFilename =
        "sumi_webkit_runtime_compat.js"
    nonisolated static let webKitRuntimeCompatibilityServiceWorkerWrapperFilename =
        "sumi_webkit_runtime_compat_worker.js"
    nonisolated static let webKitRuntimeBlockProgrammaticContentScriptAPIsKey =
        "debug.extensions.webkitRuntime.blockProgrammaticContentScriptAPIs.enabled"
    nonisolated static let selectiveContentScriptGuardTargetsKey =
        "extensions.webkitRuntime.contentScriptGuard.targets"
    nonisolated static let externallyConnectableNativeBridgeHandlerName =
        "sumiExternallyConnectableRuntime"
    nonisolated static let externallyConnectableBridgeDebugLoggingKey =
        "debug.extensions.externallyConnectable.bridge.logging.enabled"
    nonisolated static let manifestPatchCacheStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.webkitManifestPatchCache.v1"
    nonisolated static let orphanedExtensionCleanupDefaultsKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.orphanedPackageCleanup.lastRunAt"
    nonisolated static let orphanedExtensionCleanupInterval: TimeInterval =
        24 * 60 * 60
    #if DEBUG
        nonisolated static let testControllerIdentifiersDefaultsKey =
            "\(SumiAppIdentity.bundleIdentifier).tests.WKWebExtensionController.Identifiers"
        nonisolated static let installTestControllerStorageCleanupAtExit: Void = {
            atexit {
                ExtensionManager.removeRegisteredTestWebExtensionControllerStorage()
            }
        }()
    #endif
    nonisolated static let externallyConnectablePageBridgeMarker =
        "SUMI_EC_PAGE_BRIDGE:"
    nonisolated static let extensionSchemes: Set<String> = [
        "webkit-extension",
        "safari-web-extension",
    ]

    @Published var installedExtensions: [InstalledExtension] = []
    @Published private(set) var isExtensionSupportAvailable =
        ExtensionUtils.isExtensionSupportAvailable
    @Published var extensionsLoaded = false
    @Published var isPopupActive = false
    @Published var pinnedToolbarExtensionIDs: [String] = []

    enum ExtensionBackgroundWakeReason: String, Codable, CaseIterable {
        case startup
        case install
        case actionPopup
        case toolbarAction
        case externallyConnectable
        case nativeMessaging
        case reload
    }

    enum BackgroundRuntimeState: String, Codable, CaseIterable {
        case neverLoaded
        case wakeInFlight
        case loaded
        case loadFailed
    }

    struct ExtensionRuntimeMetrics: Codable, Equatable {
        var manifestPatchDuration: TimeInterval = 0
        var manifestValidationDuration: TimeInterval = 0
        var webExtensionCreationDuration: TimeInterval = 0
        var contextLoadDuration: TimeInterval = 0
        var backgroundWakeDuration: TimeInterval = 0
        var backgroundWakeCount: Int = 0
        var lastBackgroundWakeReason: ExtensionBackgroundWakeReason?
        var lastBackgroundWakeFailed = false
        var errorUpdateDuration: TimeInterval = 0
    }

    enum ExtensionRuntimeState: String, Codable, CaseIterable {
        case idle
        case loading
        case ready
        case unavailable
        case failed
    }

    enum ExtensionRuntimeRequestReason: String, Codable, CaseIterable {
        case attach
        case webViewConfiguration
        case install
        case enable
        case refresh
        case extensionAction
        case externallyConnectable
        case resetReload
    }

    let context: ModelContext
    let browserConfiguration: BrowserConfiguration
    var controllerIdentifierStorage: UUID?
    var controllerIdentifier: UUID {
        ensureRuntimeControllerIdentifier()
    }

    weak var browserManager: BrowserManager?
    var extensionController: WKWebExtensionController?
    var runtimeState: ExtensionRuntimeState = .idle
    var runtimeInitializationTask: Task<Void, Never>?
    var extensionContexts: [String: WKWebExtensionContext] = [:]
    var loadedExtensionManifests: [String: [String: Any]] = [:]
    var backgroundWakeTasks: [String: Task<Void, Error>] = [:]
    var backgroundRuntimeStateByExtensionID: [String: BackgroundRuntimeState] = [:]
    var runtimeMetricsByExtensionID: [String: ExtensionRuntimeMetrics] = [:]
    var actionAnchors: [String: [WeakAnchor]] = [:]
    var anchorObserverTokens: [String: [ObjectIdentifier: NSObjectProtocol]] = [:]
    var extensionErrorObserverTokens: [String: NSObjectProtocol] = [:]
    var lastLoggedExtensionErrorFingerprints: [String: String] = [:]
    var optionsWindows: [String: NSWindow] = [:]
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    var installedPageBridgeIDs: Set<String> = []
    var externallyConnectablePolicies: [String: ExternallyConnectablePolicy] = [:]
    var nativeMessagePortHandlers: [ObjectIdentifier: NativeMessagingHandler] = [:]
    var nativeMessagePortExtensionIDs: [ObjectIdentifier: String] = [:]
    var profileExtensionStores: [UUID: WKWebsiteDataStore] = [:]
    var profileExtensionStoreOrder: [UUID] = []
    var recentExtensionTabOpenRequests = BoundedRecentDateTracker(
        ttl: ExtensionManager.recentExtensionTabOpenRequestTTL,
        maxKeys: 128,
        maxDatesPerKey: 4
    )
    let ecRegistry = ExternallyConnectablePortRegistry()
    private(set) lazy var ecBroker: SumiExtensionMessageBroker = {
        let broker = SumiExtensionMessageBroker(
            context: Self.externallyConnectableNativeBridgeHandlerName
        )
        let pageSubfeature = ExternallyConnectablePageSubfeature(manager: self)
        let isolatedSubfeature = ExternallyConnectableIsolatedSubfeature(manager: self)
        broker.registerSubfeature(pageSubfeature)
        broker.registerSubfeature(isolatedSubfeature)
        return broker
    }()
    var extensionLoadGeneration: UInt64 = 0
    var tabOpenNotificationGeneration: UInt64 = 1

    var currentProfileId: UUID?
    var pinnedToolbarExtensionIDsByProfile: [String: [String]] = [:]

    nonisolated static let profileExtensionStoreLimit = 4
    nonisolated static let recentExtensionTabOpenRequestTTL: TimeInterval = 2

    init(
        context: ModelContext,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration = .shared
    ) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.init")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.init", signpostState)
        }

        self.context = context
        self.browserConfiguration = browserConfiguration
        self.currentProfileId = initialProfile?.id
        self.pinnedToolbarExtensionIDsByProfile = Self.loadPinnedToolbarExtensionIDsByProfile()
        self.pinnedToolbarExtensionIDs = Self.normalizedPinnedToolbarExtensionIDs(
            pinnedToolbarExtensionIDsByProfile[
                Self.pinnedToolbarProfileKey(for: initialProfile?.id)
            ] ?? []
        )
        super.init()

        guard isExtensionSupportAvailable else {
            extensionsLoaded = true
            runtimeState = .unavailable
            return
        }

        loadInstalledExtensionMetadata()
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeDeferred")
    }

    @discardableResult
    private func ensureRuntimeControllerIdentifier() -> UUID {
        if let controllerIdentifierStorage {
            return controllerIdentifierStorage
        }

        let identifier = Self.makeRuntimeControllerIdentifier()
        controllerIdentifierStorage = identifier
        return identifier
    }

    private static func makeRuntimeControllerIdentifier() -> UUID {
        #if DEBUG
            if RuntimeDiagnostics.isRunningTests {
                _ = installTestControllerStorageCleanupAtExit
                let uuid = UUID()
                registerTestWebExtensionControllerIdentifier(uuid)
                return uuid
            }
        #endif

        if let raw = UserDefaults.standard.string(forKey: controllerIdentifierKey),
           let uuid = UUID(uuidString: raw)
        {
            return uuid
        }

        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: controllerIdentifierKey)
        return uuid
    }

    #if DEBUG
        nonisolated private static func registerTestWebExtensionControllerIdentifier(
            _ controllerIdentifier: UUID
        ) {
            var identifiers = UserDefaults.standard.stringArray(
                forKey: testControllerIdentifiersDefaultsKey
            ) ?? []
            identifiers.append(controllerIdentifier.uuidString.uppercased())
            UserDefaults.standard.set(
                Array(Set(identifiers)).sorted(),
                forKey: testControllerIdentifiersDefaultsKey
            )
        }

        nonisolated private static func removeRegisteredTestWebExtensionControllerStorage() {
            let identifiers = UserDefaults.standard.stringArray(
                forKey: testControllerIdentifiersDefaultsKey
            ) ?? []
            for identifier in identifiers {
                guard let uuid = UUID(uuidString: identifier) else {
                    continue
                }
                removeTestWebExtensionControllerStorageIfNeeded(for: uuid)
            }
            UserDefaults.standard.removeObject(
                forKey: testControllerIdentifiersDefaultsKey
            )
        }

        nonisolated private static func removeTestWebExtensionControllerStorageIfNeeded(
            for controllerIdentifier: UUID
        ) {
            guard RuntimeDiagnostics.isRunningTests else {
                return
            }
            guard let libraryDirectory = FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first else {
                return
            }

            let storageURL = libraryDirectory
                .appendingPathComponent("WebKit", isDirectory: true)
                .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
                .appendingPathComponent("WebExtensions", isDirectory: true)
                .appendingPathComponent(controllerIdentifier.uuidString.uppercased(), isDirectory: true)
            try? FileManager.default.removeItem(at: storageURL)
        }
    #endif

    deinit {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.deinit")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.deinit", signpostState)
        }

        MainActor.assumeIsolated { [self] in
            tearDownExtensionRuntime(
                reason: "deinit",
                removeUIState: true,
                releaseController: true
            )
        }

        #if DEBUG
            if let controllerIdentifierStorage {
                Self.removeTestWebExtensionControllerStorageIfNeeded(
                    for: controllerIdentifierStorage
                )
            }
            clearDebugState()
        #endif
    }

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

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.resetInjectedBrowserConfigurationRuntimeState"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.resetInjectedBrowserConfigurationRuntimeState",
                signpostState
            )
        }

        tearDownExtensionRuntime(
            reason: "resetInjectedBrowserConfigurationRuntimeState",
            removeUIState: true,
            releaseController: true
        )
    }

    func refreshFromPersistence() {
        loadInstalledExtensions()
    }

    func getExtensionContext(for extensionId: String) -> WKWebExtensionContext? {
        extensionContexts[extensionId]
    }

    func windowAdapter(for windowId: UUID) -> ExtensionWindowAdapter? {
        guard let browserManager else { return nil }
        guard browserManager.windowRegistry?.windows[windowId] != nil else {
            return nil
        }

        if let existing = windowAdapters[windowId] {
            return existing
        }

        let created = ExtensionWindowAdapter(
            windowId: windowId,
            browserManager: browserManager,
            extensionManager: self
        )
        windowAdapters[windowId] = created
        return created
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let browserManager else { return nil }

        if let existing = tabAdapters[tab.id] {
            return existing
        }

        let created = ExtensionTabAdapter(
            tabId: tab.id,
            browserManager: browserManager,
            extensionManager: self
        )
        tabAdapters[tab.id] = created
        return created
    }

    static func isManagedExternallyConnectablePageBridgeScript(
        _ script: WKUserScript
    ) -> Bool {
        script.source.contains(externallyConnectablePageBridgeMarker)
    }

    static var isExternallyConnectableBridgeDebugLoggingEnabled: Bool {
        RuntimeDiagnostics.isVerboseEnabled
            || RuntimeDiagnostics.debugDefaultBool(
                forKey: externallyConnectableBridgeDebugLoggingKey
            )
    }

    nonisolated static var externallyConnectableBridgeDebugLoggingLiteral: String {
        let isEnabled = RuntimeDiagnostics.isVerboseEnabled
            || RuntimeDiagnostics.debugDefaultBool(
                forKey: externallyConnectableBridgeDebugLoggingKey
            )
        return isEnabled ? "true" : "false"
    }

    nonisolated static var isWebKitRuntimeTraceEnabled: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static var shouldObserveExtensionErrors: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static func isExtensionOwnedURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return extensionSchemes.contains(scheme)
    }

    func extensionRuntimeTrace(
        _ message: @autoclosure () -> String
    ) {
        guard Self.isWebKitRuntimeTraceEnabled else { return }
        let renderedMessage = message()
        RuntimeDiagnostics.logger(category: "ExtensionRuntimeTrace")
            .debug("\(renderedMessage, privacy: .public)")
    }

    func extensionRuntimeTrace(_ message: () -> String) {
        guard Self.isWebKitRuntimeTraceEnabled else { return }
        let renderedMessage = message()
        RuntimeDiagnostics.logger(category: "ExtensionRuntimeTrace")
            .debug("\(renderedMessage, privacy: .public)")
    }

    func recordRuntimeMetric(
        for extensionId: String,
        update: (inout ExtensionRuntimeMetrics) -> Void
    ) {
        var metrics = runtimeMetricsByExtensionID[extensionId] ?? ExtensionRuntimeMetrics()
        update(&metrics)
        runtimeMetricsByExtensionID[extensionId] = metrics
    }

    func extensionRuntimeObjectDescription(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(describing: Unmanaged.passUnretained(object).toOpaque())
    }

    func extensionRuntimeControllerDescription(
        _ controller: WKWebExtensionController?
    ) -> String {
        extensionRuntimeObjectDescription(controller)
    }

    func extensionRuntimeConfigurationDescription(
        _ configuration: WKWebViewConfiguration?
    ) -> String {
        extensionRuntimeObjectDescription(configuration)
    }

    func extensionRuntimeUserContentControllerDescription(
        _ userContentController: WKUserContentController?
    ) -> String {
        extensionRuntimeObjectDescription(userContentController)
    }

    func extensionRuntimeWebViewDescription(_ webView: WKWebView?) -> String {
        extensionRuntimeObjectDescription(webView)
    }

    func extensionRuntimeTabDescription(_ tab: Tab) -> String {
        let webViews = [tab.assignedWebView, tab.existingWebView]
            .compactMap { $0 }
            .map { extensionRuntimeWebViewDescription($0) }
            .joined(separator: ",")
        let resolvedURL = tab.assignedWebView?.url?.absoluteString
            ?? tab.existingWebView?.url?.absoluteString
            ?? tab.url.absoluteString
        return "tab=\(tab.id.uuidString.prefix(8)) url=\(resolvedURL) webViews=[\(webViews)]"
    }
}
