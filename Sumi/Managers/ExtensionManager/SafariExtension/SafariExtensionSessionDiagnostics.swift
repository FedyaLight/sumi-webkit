//
//  SafariExtensionSessionDiagnostics.swift
//  Sumi
//
//  Sanitized auth/session diagnostics for Safari Web Extension popup + tab flows.
//  Never logs cookie values, storage payloads, tokens, or message bodies.
//

import Foundation
import WebKit

/// Precise generic failure buckets for extension auth/session visibility gaps.
enum SafariExtensionSessionFailureBucket: String, Codable, CaseIterable, Sendable {
    case none
    case cookieStoreNotShared
    case extensionStorageNotPersisted
    case popupContextReset
    case navigationEventNotDelivered
    case runtimeMessageNotDelivered
    case hostPermissionDenied
    case callbackURLNotHandled
    case webKitPlatformLimitation
    case unknown
}

enum SafariExtensionPopupLifecyclePhase: String, Codable, Sendable {
    case opened
    case reopened
    case closed
}

struct SafariExtensionWebsiteDataStoreSnapshot: Codable, Equatable, Sendable {
    let identifier: String?
    let isPersistent: Bool
    let matchesProfileStore: Bool
    let matchesExtensionControllerDefaultStore: Bool
    let matchesActiveTabStore: Bool
}

struct SafariExtensionCookieDomainCount: Codable, Equatable, Sendable {
    let domain: String
    let count: Int
}

struct SafariExtensionSessionDiagnostic: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(extensionId)-\(phase.rawValue)-\(recordedAt.timeIntervalSince1970)" }

    let recordedAt: Date
    let extensionId: String
    let phase: SafariExtensionPopupLifecyclePhase
    let safariRuntimeLoadSource: SafariAppExtensionRuntimeLoadSource?
    let popupUsesOriginalAppex: Bool
    let extensionContextLoaded: Bool
    let popupWebViewPresent: Bool
    let isPopupActive: Bool
    let activeTabStore: SafariExtensionWebsiteDataStoreSnapshot?
    let extensionControllerDefaultStore: SafariExtensionWebsiteDataStoreSnapshot?
    let extensionPageConfigurationStore: SafariExtensionWebsiteDataStoreSnapshot?
    let popupWebViewStore: SafariExtensionWebsiteDataStoreSnapshot?
    let cookieDomainCounts: [SafariExtensionCookieDomainCount]
    let permissionBucketSummary: String
    let inferredFailureBucket: SafariExtensionSessionFailureBucket
    let note: String
}

@MainActor
enum SafariExtensionSessionDiagnosticsBuilder {
    static func build(
        extensionId: String,
        phase: SafariExtensionPopupLifecyclePhase,
        extensionManager: ExtensionManager,
        popupWebView: WKWebView? = nil
    ) async -> SafariExtensionSessionDiagnostic {
        let installed = extensionManager.installedExtensions.first { $0.id == extensionId }
        let activeTab = extensionManager.browserManager?.currentTabForActiveWindow()
        let activeProfileId =
            activeTab.flatMap { extensionManager.resolvedProfileId(for: $0) }
            ?? extensionManager.browserManager?.currentProfile?.id
        let context = extensionManager.getExtensionContext(
            for: extensionId,
            profileId: activeProfileId
        )
        let safariRuntimeLoadSource: SafariAppExtensionRuntimeLoadSource? = {
            guard let installed, installed.sourceKind == .safariAppExtension else {
                return nil
            }
            if SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installed.sourceKind,
                sourceBundlePath: installed.sourceBundlePath
            ) != nil {
                return .originalAppexBundle
            }
            return nil
        }()

        let profileStore =
            activeProfileId.flatMap { profileId in
                extensionManager.browserManager?.profileManager.profiles
                    .first(where: { $0.id == profileId })?.dataStore
            }
            ?? extensionManager.browserManager?.currentProfile?.dataStore
        let controllerDefaultStore =
            activeProfileId
            .flatMap { extensionManager.extensionControllersByProfile[$0] }?
            .configuration.defaultWebsiteDataStore
        let pageConfigurationStore =
            activeProfileId
            .flatMap { extensionManager.extensionControllersByProfile[$0] }?
            .configuration.webViewConfiguration?
            .websiteDataStore
        let activeTabStore: WKWebsiteDataStore? = {
            guard let activeTab,
                  let browserManager = extensionManager.browserManager,
                  let activeWindow = browserManager.windowRegistry?.activeWindow,
                  let webView = browserManager.windowOwnedWebView(
                      for: activeTab,
                      in: activeWindow.id
                  )
            else {
                return nil
            }
            return webView.configuration.websiteDataStore
        }()

        let profileSnapshot = snapshot(for: profileStore)
        let controllerSnapshot = snapshot(for: controllerDefaultStore)
        let pageSnapshot = snapshot(for: pageConfigurationStore)
        let tabSnapshot = snapshot(for: activeTabStore)
        let popupSnapshot = snapshot(for: popupWebView?.configuration.websiteDataStore)

        let storeAlignedWithProfile =
            profileSnapshot?.identifier != nil
            && pageSnapshot?.identifier == profileSnapshot?.identifier
            && controllerSnapshot?.identifier == profileSnapshot?.identifier
        let popupAlignedWithProfile =
            popupSnapshot == nil
            || popupSnapshot?.identifier == profileSnapshot?.identifier

        let cookieDomainCounts = await cookieDomainCounts(
            in: profileStore,
            domains: observedAuthDomains(for: installed)
        )

        let inferredBucket = inferFailureBucket(
            storeAlignedWithProfile: storeAlignedWithProfile,
            popupAlignedWithProfile: popupAlignedWithProfile,
            extensionContextLoaded: context != nil,
            popupWebViewPresent: popupWebView != nil,
            isPopupActive: extensionManager.isPopupActive
        )

        return SafariExtensionSessionDiagnostic(
            recordedAt: Date(),
            extensionId: extensionId,
            phase: phase,
            safariRuntimeLoadSource: safariRuntimeLoadSource,
            popupUsesOriginalAppex: safariRuntimeLoadSource == .originalAppexBundle,
            extensionContextLoaded: context != nil,
            popupWebViewPresent: popupWebView != nil,
            isPopupActive: extensionManager.isPopupActive,
            activeTabStore: enrichedSnapshot(
                tabSnapshot,
                profileStore: profileStore,
                controllerStore: controllerDefaultStore,
                activeTabStore: activeTabStore
            ),
            extensionControllerDefaultStore: enrichedSnapshot(
                controllerSnapshot,
                profileStore: profileStore,
                controllerStore: controllerDefaultStore,
                activeTabStore: activeTabStore
            ),
            extensionPageConfigurationStore: enrichedSnapshot(
                pageSnapshot,
                profileStore: profileStore,
                controllerStore: controllerDefaultStore,
                activeTabStore: activeTabStore
            ),
            popupWebViewStore: enrichedSnapshot(
                popupSnapshot,
                profileStore: profileStore,
                controllerStore: controllerDefaultStore,
                activeTabStore: activeTabStore
            ),
            cookieDomainCounts: cookieDomainCounts,
            permissionBucketSummary: permissionBucketSummary(for: context),
            inferredFailureBucket: inferredBucket,
            note: storeAlignedWithProfile
                ? "Extension runtime website data stores match the active profile store."
                : "Extension runtime website data stores diverge from the active profile store."
        )
    }

    static func logIfDiagnosticsEnabled(_ diagnostic: SafariExtensionSessionDiagnostic) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(diagnostic),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        RuntimeDiagnostics.debug(
            "SafariExtensionSessionDiagnostic \(json)",
            category: "Extensions"
        )
    }

    private static func snapshot(for store: WKWebsiteDataStore?) -> SafariExtensionWebsiteDataStoreSnapshot? {
        guard let store else { return nil }
        return SafariExtensionWebsiteDataStoreSnapshot(
            identifier: store.identifier?.uuidString,
            isPersistent: store.isPersistent,
            matchesProfileStore: false,
            matchesExtensionControllerDefaultStore: false,
            matchesActiveTabStore: false
        )
    }

    private static func enrichedSnapshot(
        _ snapshot: SafariExtensionWebsiteDataStoreSnapshot?,
        profileStore: WKWebsiteDataStore?,
        controllerStore: WKWebsiteDataStore?,
        activeTabStore: WKWebsiteDataStore?
    ) -> SafariExtensionWebsiteDataStoreSnapshot? {
        guard let snapshot else { return nil }
        return SafariExtensionWebsiteDataStoreSnapshot(
            identifier: snapshot.identifier,
            isPersistent: snapshot.isPersistent,
            matchesProfileStore: identifiersEqual(snapshot.identifier, profileStore?.identifier?.uuidString),
            matchesExtensionControllerDefaultStore: identifiersEqual(
                snapshot.identifier,
                controllerStore?.identifier?.uuidString
            ),
            matchesActiveTabStore: identifiersEqual(
                snapshot.identifier,
                activeTabStore?.identifier?.uuidString
            )
        )
    }

    private static func identifiersEqual(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func observedAuthDomains(for installed: InstalledExtension?) -> [String] {
        guard let hostPermissions = installed?.manifest["host_permissions"] as? [String] else {
            return []
        }
        return hostPermissions.compactMap { pattern in
            guard pattern.hasPrefix("https://") || pattern.hasPrefix("http://") else {
                return nil
            }
            return URL(string: pattern)?.host
        }
        .filter { $0.isEmpty == false }
    }

    private static func cookieDomainCounts(
        in store: WKWebsiteDataStore?,
        domains: [String]
    ) async -> [SafariExtensionCookieDomainCount] {
        guard let store, domains.isEmpty == false else { return [] }

        let cookies = await store.httpCookieStore.allCookies()
        return domains.map { domain in
            let count = cookies.filter {
                $0.domain == domain
                    || $0.domain == ".\(domain)"
                    || domain.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }.count
            return SafariExtensionCookieDomainCount(domain: domain, count: count)
        }
        .sorted { $0.domain < $1.domain }
    }

    private static func permissionBucketSummary(
        for context: WKWebExtensionContext?
    ) -> String {
        guard let context else { return "contextMissing" }
        let grantedPermissions = context.grantedPermissionMatchPatterns.count
        let requestedPermissions = context.webExtension.requestedPermissions.count
        return "grantedHostPatterns=\(grantedPermissions) requestedPermissions=\(requestedPermissions)"
    }

    private static func inferFailureBucket(
        storeAlignedWithProfile: Bool,
        popupAlignedWithProfile: Bool,
        extensionContextLoaded: Bool,
        popupWebViewPresent: Bool,
        isPopupActive: Bool
    ) -> SafariExtensionSessionFailureBucket {
        if extensionContextLoaded == false {
            return .unknown
        }
        if storeAlignedWithProfile == false || popupAlignedWithProfile == false {
            return .cookieStoreNotShared
        }
        if popupWebViewPresent == false && isPopupActive {
            return .popupContextReset
        }
        return .none
    }
}
