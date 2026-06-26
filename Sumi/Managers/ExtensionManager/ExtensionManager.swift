//
//  ExtensionManager.swift
//  Sumi
//
//  WebExtension runtime rebuilt on top of native WebKit APIs.
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
    static let safariWebExtensionURLScheme = "safari-web-extension"
    static let registerSafariWebExtensionURLScheme: Void = {
        WKWebExtension.MatchPattern.registerCustomURLScheme(
            safariWebExtensionURLScheme
        )
    }()
    static let controllerIdentifierKey =
        "\(SumiAppIdentity.bundleIdentifier).WKWebExtensionController.Identifier"
    nonisolated static let orphanedExtensionCleanupDefaultsKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.orphanedPackageCleanup.lastRunAt"
    nonisolated static let orphanedExtensionCleanupInterval: TimeInterval =
        24 * 60 * 60
    nonisolated static let extensionPermissionDecisionsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.permissionDecisions.v1"
    nonisolated static let extensionSiteAccessStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.siteAccess.v1"
    #if DEBUG
        nonisolated static let testControllerIdentifiersDefaultsKey =
            "\(SumiAppIdentity.bundleIdentifier).tests.WKWebExtensionController.Identifiers"
        nonisolated static let installTestControllerStorageCleanupAtExit: Void = {
            atexit {
                ExtensionManager.removeRegisteredTestWebExtensionControllerStorage()
            }
        }()
    #endif
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]
    @Published private(set) var isExtensionSupportAvailable =
        ExtensionUtils.isExtensionSupportAvailable
    @Published var extensionsLoaded = false
    @Published var isPopupActive = false
    var activePopupExtensionID: String?
    @Published var pinnedToolbarExtensionIDs: [String] = []

    enum ExtensionBackgroundWakeReason: String, Codable, CaseIterable {
        case startup
        case install
        case enable
        case actionPopup
        case toolbarAction
        case nativeMessaging
    }

    enum BackgroundRuntimeState: String, Codable, CaseIterable {
        case neverLoaded
        case wakeInFlight
        case loaded
        case loadFailed
    }

    struct ExtensionRuntimeMetrics: Codable, Equatable {
        var manifestValidationDuration: TimeInterval = 0
        var webExtensionCreationDuration: TimeInterval = 0
        var contextLoadDuration: TimeInterval = 0
        var backgroundWakeDuration: TimeInterval = 0
        var backgroundWakeCount: Int = 0
        var lastBackgroundWakeReason: ExtensionBackgroundWakeReason?
        var lastBackgroundWakeFailed = false
        var errorUpdateDuration: TimeInterval = 0
    }

    struct WebExtensionRuntimeSourceKey: Equatable {
        let sourceKind: WebExtensionSourceKind
        let sourceBundlePath: String
        let packageRootPath: String
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
        case resetReload
    }

    enum ExtensionPermissionPromptDecision {
        case allow(expirationDate: Date?)
        case deny
    }

    enum ExtensionPermissionTargetKind: String, Codable {
        case permission
        case matchPattern
    }

    enum ExtensionStoredPermissionState: String, Codable {
        case allowed
        case denied
    }

    struct ExtensionStoredPermissionDecision: Codable, Equatable {
        var profileId: String
        var extensionId: String
        var targetKind: ExtensionPermissionTargetKind
        var target: String
        var state: ExtensionStoredPermissionState
        var expiresAt: Date?
        var updatedAt: Date

        func isExpired(now: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }

    let context: ModelContext
    let browserConfiguration: BrowserConfiguration
    var controllerIdentifierStorage: UUID?
    var controllerIdentifier: UUID {
        ensureRuntimeControllerIdentifier()
    }

    weak var browserManager: BrowserManager?
    weak var browserBridgeContext: (any ExtensionBrowserBridgeContext)?
    var profileRuntimeState = ExtensionProfileRuntimeState()
    var extensionControllersByProfile: [UUID: WKWebExtensionController] {
        get { profileRuntimeState.controllersByProfile }
        set { profileRuntimeState.replaceControllers(newValue) }
    }
    var extensionContextsByProfile: [UUID: [String: WKWebExtensionContext]] {
        get { profileRuntimeState.contextsByProfile }
        set { profileRuntimeState.replaceContexts(newValue) }
    }
    var extensionContextBindingGenerationByProfile: [UUID: UInt64] {
        get { profileRuntimeState.contextBindingGenerationByProfile }
        set { profileRuntimeState.replaceContextBindingGenerations(newValue) }
    }
    /// Parsed extension resources are profile-agnostic; each profile gets its own context.
    var cachedWebExtensionsByID: [String: WKWebExtension] = [:]
    var cachedWebExtensionRuntimeSourceKeysByID: [String: WebExtensionRuntimeSourceKey] = [:]
    var lastExtensionLoadErrors: [String: Error] = [:]
    var extensionRuntimeResidencyState = ExtensionRuntimeResidencyState()
    var runtimeState: ExtensionRuntimeState = .idle
    var extensionRuntimeAllowsWithoutEnabledExtensions = false
    var runtimeInitializationTask: Task<Void, Never>?
    var loadedExtensionManifests: [String: [String: Any]] = [:]
    var backgroundWakeTasks: [String: Task<Void, Error>] = [:]
    var backgroundRuntimeStateByExtensionID: [String: BackgroundRuntimeState] = [:]
    var runtimeMetricsByExtensionID: [String: ExtensionRuntimeMetrics] = [:]
    var actionAnchors: [String: [WeakAnchor]] = [:]
    var pendingActionPopupAnchors: [UUID: ExtensionActionPopupAnchor] = [:]
    var latestActionPopupAnchorSessionByExtensionID: [String: UUID] = [:]
    var anchorObserverTokens: [String: [ObjectIdentifier: NSObjectProtocol]] = [:]
    var extensionErrorObserverTokens: [String: NSObjectProtocol] = [:]
    var lastLoggedExtensionErrorFingerprints: [String: String] = [:]
    var optionsWindows: [String: NSWindow] = [:]
    var optionsWindowDelegates: [String: ExtensionOptionsWindowDelegate] = [:]
    weak var activeExtensionActionPopover: NSPopover?
    var extensionActionPopupUIDelegates: [String: ExtensionActionPopupUIDelegate] = [:]
    var deferredPopupContextUnloadTasks: [String: Task<Void, Never>] = [:]
    var deferredPopupContextUnloadProfileIDs: [String: UUID] = [:]
    var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    var windowAdapters: [UUID: ExtensionWindowAdapter] = [:]
    var miniWindowAdapters: [UUID: ExtensionMiniWindowAdapter] = [:]
    var nativeMessagePortHandlers: [ObjectIdentifier: NativeMessagingHandler] = [:]
    var nativeMessagePortExtensionIDs: [ObjectIdentifier: String] = [:]
    var nativeMessagePortProfileIDs: [ObjectIdentifier: UUID] = [:]
    private var nativeMessagingRelayStorage: SumiNativeMessagingRelay?
    var nativeMessagingRelay: SumiNativeMessagingRelay {
        if let nativeMessagingRelayStorage {
            return nativeMessagingRelayStorage
        }
        let relay = SumiNativeMessagingRelay()
        nativeMessagingRelayStorage = relay
        return relay
    }

    var safariNativeMessagingHost: SumiNativeMessagingRelay { nativeMessagingRelay }

    var loadedNativeMessagingRelay: SumiNativeMessagingRelay? {
        nativeMessagingRelayStorage
    }
    var profileExtensionStores: [UUID: WKWebsiteDataStore] = [:]
    var profileExtensionStoreOrder: [UUID] = []
    var privateExtensionRuntimeProfileIDs: Set<UUID> = []
    var recentExtensionTabOpenRequests = BoundedRecentDateTracker(
        ttl: ExtensionManager.recentExtensionTabOpenRequestTTL,
        maxKeys: 128,
        maxDatesPerKey: 4
    )
    var extensionLoadGeneration: UInt64 = 0
    var tabOpenNotificationGeneration: UInt64 = 1
    var contentScriptContextLoadTasksByProfile: [UUID: Task<Void, Never>] = [:]
    var initialDocumentNativeMessagingWarmupTasksByProfile: [UUID: Task<Void, Never>] = [:]
    var extensionPermissionPromptQueue: [@MainActor () -> Void] = []
    var isPresentingExtensionPermissionPrompt = false
    var extensionPermissionPromptWaitersByKey:
        [String: [CheckedContinuation<ExtensionPermissionPromptDecision, Never>]] = [:]
    var permissionsOriginsCompatibilityInstallations:
        [ObjectIdentifier: Set<String>] = [:]
    var extensionPageUserContentControllersByProfile:
        [UUID: WKUserContentController] = [:]

    var currentProfileId: UUID?
    var pinnedToolbarExtensionIDsByProfile: [String: [String]] = [:]

    nonisolated static let profileExtensionStoreLimit = 4
    nonisolated static let maxLiveExtensionContexts = 8
    nonisolated static let recentExtensionTabOpenRequestTTL: TimeInterval = 2

    init(
        context: ModelContext,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil
    ) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.init")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.init", signpostState)
        }

        _ = Self.registerSafariWebExtensionURLScheme
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.currentProfileId = initialProfile?.id
        self.pinnedToolbarExtensionIDsByProfile = Self.loadPinnedToolbarExtensionIDsByProfile()
        self.pinnedToolbarExtensionIDs = Self.normalizedPinnedToolbarExtensionIDs(
            pinnedToolbarExtensionIDsByProfile[
                Self.pinnedToolbarProfileKey(for: initialProfile?.id)
            ] ?? []
        )
        super.init()
        SafariExtensionAutofillFillDiagnostics.deferredFillCompletionHandler = {
            [weak self] extensionId in
            guard let extensionId else { return }
            self?.completeDeferredPopupContextUnload(
                forExtensionId: extensionId,
                reason: "relaySucceeded"
            )
        }

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

    isolated deinit {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.deinit")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.deinit", signpostState)
        }

        tearDownExtensionRuntime(
            reason: "deinit",
            removeUIState: true,
            releaseController: true
        )
        #if DEBUG
            clearDebugState()
        #endif

        #if DEBUG
            if let controllerIdentifierStorage {
                Self.removeTestWebExtensionControllerStorageIfNeeded(
                    for: controllerIdentifierStorage
                )
            }
        #endif
    }

    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        browserBridgeContext?.auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        guard let browserBridgeContext else { return nil }

        if let existing = miniWindowAdapters[sessionId] {
            return existing
        }

        let created = ExtensionMiniWindowAdapter(
            sessionId: sessionId,
            tabId: tab.id,
            window: window,
            browserContext: browserBridgeContext,
            extensionManager: self,
            isPrivate: isPrivate,
            shouldActivateApp: shouldActivateApp
        )
        miniWindowAdapters[sessionId] = created
        return created
    }

    func windowAdapter(for windowId: UUID) -> ExtensionWindowAdapter? {
        guard let browserBridgeContext else { return nil }
        guard browserBridgeContext.extensionWindowState(for: windowId) != nil else {
            return nil
        }

        if let existing = windowAdapters[windowId] {
            return existing
        }

        let created = ExtensionWindowAdapter(
            windowId: windowId,
            browserContext: browserBridgeContext,
            extensionManager: self
        )
        windowAdapters[windowId] = created
        return created
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let browserBridgeContext else { return nil }

        if let existing = tabAdapters[tab.id] {
            return existing
        }

        let created = ExtensionTabAdapter(
            tabId: tab.id,
            browserContext: browserBridgeContext,
            extensionManager: self
        )
        tabAdapters[tab.id] = created
        return created
    }

    func normalTabUserScripts() -> [SumiUserScript] {
        []
    }

    nonisolated static var isWebKitRuntimeTraceEnabled: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static var shouldObserveExtensionErrors: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static func isExtensionOwnedURL(_ url: URL?) -> Bool {
        ExtensionUtils.isExtensionOwnedURL(url)
    }

    func extensionRuntimeTrace(
        _ message: @autoclosure () -> String
    ) {
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

    func traceNativeMessagingContextBinding(
        phase: String,
        extensionId: String?,
        profileId: UUID?,
        loadSource: SafariAppExtensionRuntimeLoadSource? = nil,
        webExtension: WKWebExtension? = nil,
        extensionContext: WKWebExtensionContext? = nil,
        controller: WKWebExtensionController? = nil,
        configuration: WKWebViewConfiguration? = nil,
        webView: WKWebView? = nil
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let profileController = profileId.flatMap {
                extensionControllersByProfile[$0]
            }
            let effectiveController = controller ?? configuration?.webExtensionController
                ?? webView?.configuration.webExtensionController
                ?? extensionContext?.webViewConfiguration?.webExtensionController
                ?? profileController
            let delegate = effectiveController?.delegate
            let delegateObject = delegate.map { $0 as AnyObject }
            let delegateNSObject: NSObjectProtocol? = delegate
            let sendSelector = #selector(
                WKWebExtensionControllerDelegate.webExtensionController(
                    _:sendMessage:toApplicationWithIdentifier:for:replyHandler:
                )
            )
            let connectSelector = #selector(
                WKWebExtensionControllerDelegate.webExtensionController(
                    _:connectUsing:for:completionHandler:
                )
            )
            let controllerOwnsContext: String = {
                guard let effectiveController, let extensionContext else { return "-" }
                return String(
                    effectiveController.extensionContext(for: extensionContext.baseURL)
                        === extensionContext
                )
            }()
            let nativeMessagingGranted: String = {
                guard let extensionContext else { return "-" }
                return String(
                    isGrantedPermissionStatus(
                        extensionContext.permissionStatus(for: .nativeMessaging)
                    )
                )
            }()
            let unsupportedNativeMessaging: String = {
                guard let extensionContext else { return "-" }
                return String(
                    extensionContext.unsupportedAPIs.contains {
                        $0.localizedCaseInsensitiveContains("nativeMessaging")
                    }
                )
            }()
            let configurationController = configuration?.webExtensionController
            let webViewController = webView?.configuration.webExtensionController
            let contextConfigurationController =
                extensionContext?.webViewConfiguration?.webExtensionController
            let delegateIsSumi: Bool = {
                guard let delegateObject else { return false }
                return delegateObject === self
            }()
            let controllerIsProfile: Bool = {
                guard let effectiveController, let profileController else { return false }
                return effectiveController === profileController
            }()
            let contextConfigurationControllerMatches: Bool = {
                guard let contextConfigurationController, let effectiveController else {
                    return false
                }
                return contextConfigurationController === effectiveController
            }()
            let configurationControllerMatches: Bool = {
                guard let configurationController, let effectiveController else { return false }
                return configurationController === effectiveController
            }()
            let webViewControllerMatches: Bool = {
                guard let webViewController, let effectiveController else { return false }
                return webViewController === effectiveController
            }()
            let delegateRespondsToSend = delegateNSObject?.responds(to: sendSelector) ?? false
            let delegateRespondsToConnect = delegateNSObject?.responds(to: connectSelector) ?? false

            RuntimeDiagnostics.debug(category: "SafariNativeMessagingContext") {
                """
                phase=\(phase) \
                extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                loadSource=\(loadSource?.rawValue ?? "-") \
                webExtension=\(extensionRuntimeObjectDescription(webExtension)) \
                context=\(extensionRuntimeObjectDescription(extensionContext)) \
                controller=\(extensionRuntimeControllerDescription(effectiveController)) \
                profileController=\(extensionRuntimeControllerDescription(profileController)) \
                controllerIsProfile=\(controllerIsProfile) \
                controllerOwnsContext=\(controllerOwnsContext) \
                nativeMessagingGranted=\(nativeMessagingGranted) \
                unsupportedNativeMessaging=\(unsupportedNativeMessaging) \
                delegate=\(delegateObject.map { String(describing: type(of: $0)) } ?? "nil") \
                delegateIsSumi=\(delegateIsSumi) \
                delegateSend=\(delegateRespondsToSend) \
                delegateConnect=\(delegateRespondsToConnect) \
                contextConfigControllerMatches=\(contextConfigurationControllerMatches) \
                configControllerMatches=\(configurationControllerMatches) \
                webViewControllerMatches=\(webViewControllerMatches)
                """
            }
        #else
            _ = (
                phase,
                extensionId,
                profileId,
                loadSource,
                webExtension,
                extensionContext,
                controller,
                configuration,
                webView
            )
        #endif
    }

    func nativeMessagingLoadSource(for extensionId: String?) -> SafariAppExtensionRuntimeLoadSource? {
        guard let extensionId,
              let installed = installedExtensions.first(where: { $0.id == extensionId })
        else { return nil }
        return installed.sourceKind == .safariAppExtension
            ? .originalAppexBundle
            : .copiedPackage
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
