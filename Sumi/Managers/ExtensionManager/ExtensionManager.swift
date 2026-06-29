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
    nonisolated static let extensionPermissionDecisionsStorageKey =
        SafariExtensionSiteAccessPolicyStore.legacyPermissionDecisionsStorageKey
    nonisolated static let extensionSiteAccessStorageKey =
        SafariExtensionSiteAccessPolicyStore.siteAccessStorageKey
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
    let moduleRegistry: SumiModuleRegistry
    let installationMetadataStore: ExtensionInstallationMetadataStore
    let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
    let extensionPreferences: UserDefaults
    let requestedTabLifecycleOwner = ExtensionRequestedTabLifecycleOwner()
    let profileRuntimeOwner: ExtensionProfileRuntimeOwner
    var profileRuntimeStateOwner: ExtensionProfileRuntimeStateOwner {
        ExtensionProfileRuntimeStateOwner(manager: self)
    }
    private let controllerIdentifierOwner =
        ExtensionRuntimeControllerIdentifierOwner()
    var controllerIdentifier: UUID {
        controllerIdentifierOwner.identifier
    }

    weak var browserManager: BrowserManager?
    weak var browserBridgeContext: (any ExtensionBrowserBridgeContext)?
    var extensionControllersByProfile: [UUID: WKWebExtensionController] {
        get { profileRuntimeOwner.controllersByProfile }
        set { profileRuntimeOwner.replaceControllers(newValue) }
    }
    var extensionContextsByProfile: [UUID: [String: WKWebExtensionContext]] {
        get { profileRuntimeOwner.contextsByProfile }
        set { profileRuntimeOwner.replaceContexts(newValue) }
    }
    var extensionContextBindingGenerationByProfile: [UUID: UInt64] {
        get { profileRuntimeOwner.contextBindingGenerationsByProfile }
        set { profileRuntimeOwner.replaceContextBindingGenerations(newValue) }
    }
    let runtimeSessionOwner = ExtensionRuntimeSessionOwner()
    let installCapabilityOwner = SafariExtensionInstallCapabilityOwner()
    let backgroundRuntimeStateOwner = ExtensionBackgroundRuntimeStateOwner()
    let runtimeTeardownOwner = ExtensionRuntimeTeardownOwner()
    var nativeMessagingBackgroundWakeOwnerStorage:
        ExtensionNativeMessagingBackgroundWakeOwner?
    var nativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner {
        if let nativeMessagingBackgroundWakeOwnerStorage {
            return nativeMessagingBackgroundWakeOwnerStorage
        }
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        nativeMessagingBackgroundWakeOwnerStorage = owner
        return owner
    }
    var loadedNativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner? {
        nativeMessagingBackgroundWakeOwnerStorage
    }
    var initialDocumentRuntimePreparationOwnerStorage:
        ExtensionInitialDocumentRuntimePreparationOwner?
    var initialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner {
        if let initialDocumentRuntimePreparationOwnerStorage {
            return initialDocumentRuntimePreparationOwnerStorage
        }
        let owner = ExtensionInitialDocumentRuntimePreparationOwner(manager: self)
        initialDocumentRuntimePreparationOwnerStorage = owner
        return owner
    }
    var loadedInitialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner? {
        initialDocumentRuntimePreparationOwnerStorage
    }
    var normalTabRuntimeBindingOwnerStorage:
        ExtensionNormalTabRuntimeBindingOwner?
    var normalTabRuntimeBindingOwner:
        ExtensionNormalTabRuntimeBindingOwner {
        if let normalTabRuntimeBindingOwnerStorage {
            return normalTabRuntimeBindingOwnerStorage
        }
        let owner = ExtensionNormalTabRuntimeBindingOwner(manager: self)
        normalTabRuntimeBindingOwnerStorage = owner
        return owner
    }
    var actionAnchors: [String: [WeakAnchor]] = [:]
    let actionPopupAnchorStore = ExtensionActionPopupAnchorStore()
    var anchorObserverTokens: [String: [ObjectIdentifier: NSObjectProtocol]] = [:]
    var extensionErrorObserverTokens: [String: NSObjectProtocol] = [:]
    var lastLoggedExtensionErrorFingerprints: [String: String] = [:]
    var optionsWindows: [String: NSWindow] = [:]
    var optionsWindowDelegates: [String: ExtensionOptionsWindowDelegate] = [:]
    weak var activeExtensionActionPopover: NSPopover?
    var extensionActionPopupUIDelegates: [String: ExtensionActionPopupUIDelegate] = [:]
    var deferredPopupContextUnloadTasks: [String: Task<Void, Never>] = [:]
    var deferredPopupContextUnloadProfileIDs: [String: UUID] = [:]
    let adapterStore = ExtensionBrowserAdapterStore()
    let nativeMessagingPortRegistry = ExtensionNativeMessagingPortRegistry()
    private var nativeMessagingRelayStorage: SumiNativeMessagingRelay?
    var nativeMessagingRelay: SumiNativeMessagingRelay {
        if let nativeMessagingRelayStorage {
            return nativeMessagingRelayStorage
        }
        let relay = SumiNativeMessagingRelay.production(
            extensionsModuleEnabled: { [weak self] in
                self?.extensionsModuleEnabledForDelegateCallbacks ?? false
            },
            profileRuntimeLoaded: { [weak self] in
                guard let self else { return false }
                return self.runtimeState == .ready || self.runtimeState == .loading
            }
        )
        nativeMessagingRelayStorage = relay
        return relay
    }

    var safariNativeMessagingHost: SumiNativeMessagingRelay { nativeMessagingRelay }

    var loadedNativeMessagingRelay: SumiNativeMessagingRelay? {
        nativeMessagingRelayStorage
    }
    let extensionPermissionPromptPresentationOwner =
        ExtensionPermissionPromptPresentationOwner()
    var permissionsOriginsCompatibilityInstallations:
        [ObjectIdentifier: Set<String>] = [:]
    var extensionPageUserContentControllersByProfile:
        [UUID: WKUserContentController] = [:]

    var currentProfileId: UUID? {
        get { profileRuntimeOwner.currentProfileId }
        set { profileRuntimeOwner.currentProfileId = newValue }
    }
    var pinnedToolbarExtensionIDsByProfile: [String: [String]] = [:]

    nonisolated static let profileExtensionStoreLimit =
        ExtensionProfileWebsiteDataStoreCache.defaultLimit
    nonisolated static let maxLiveExtensionContexts = 8
    init(
        context: ModelContext,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .shared,
        extensionPreferences: UserDefaults = .standard
    ) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.init")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.init", signpostState)
        }

        _ = Self.registerSafariWebExtensionURLScheme
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.moduleRegistry = moduleRegistry
        self.extensionPreferences = extensionPreferences
        self.installationMetadataStore = ExtensionInstallationMetadataStore(
            context: context
        )
        self.siteAccessPolicyStore = SafariExtensionSiteAccessPolicyStore(
            preferences: extensionPreferences
        )
        self.profileRuntimeOwner = ExtensionProfileRuntimeOwner(
            initialProfileId: initialProfile?.id
        )
        self.pinnedToolbarExtensionIDsByProfile =
            Self.loadPinnedToolbarExtensionIDsByProfile(from: extensionPreferences)
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

        controllerIdentifierOwner.removeTestStorageIfNeededForLoadedIdentifier()
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
