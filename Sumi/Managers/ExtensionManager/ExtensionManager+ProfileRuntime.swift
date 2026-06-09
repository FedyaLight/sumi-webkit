import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var extensionController: WKWebExtensionController? {
        guard let currentProfileId else { return nil }
        return extensionControllersByProfile[currentProfileId]
    }

    var extensionContexts: [String: WKWebExtensionContext] {
        guard let currentProfileId else { return [:] }
        return extensionContextsByProfile[currentProfileId] ?? [:]
    }

    func extensionContexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        extensionContextsByProfile[profileId] ?? [:]
    }

    func setExtensionContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        var contexts = extensionContextsByProfile[profileId] ?? [:]
        contexts[extensionId] = context
        extensionContextsByProfile[profileId] = contexts
    }

    @discardableResult
    func removeExtensionContext(
        extensionId: String,
        profileId: UUID
    ) -> WKWebExtensionContext? {
        guard var contexts = extensionContextsByProfile[profileId] else {
            return nil
        }
        let removed = contexts.removeValue(forKey: extensionId)
        if contexts.isEmpty {
            extensionContextsByProfile.removeValue(forKey: profileId)
        } else {
            extensionContextsByProfile[profileId] = contexts
        }
        return removed
    }

    func allLoadedExtensionIDs() -> Set<String> {
        Set(extensionContextsByProfile.values.flatMap(\.keys))
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        for (profileId, contexts) in extensionContextsByProfile {
            if contexts.values.contains(where: { $0 === extensionContext }) {
                return profileId
            }
        }
        return nil
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        extensionControllersByProfile.first(where: { $0.value === controller })?.key
    }

    func resolvedProfileId(for tab: Tab?) -> UUID? {
        guard let tab else { return currentProfileId }
        if let profileId = tab.profileId {
            return profileId
        }
        if let profile = tab.resolveProfile() {
            return profile.id
        }
        if let windowId = tab.primaryWindowId,
           let windowState = browserManager?.windowRegistry?.windows[windowId]
        {
            return resolvedProfileId(for: windowState)
        }
        return currentProfileId ?? browserManager?.currentProfile?.id
    }

    func resolvedProfileId(for windowState: BrowserWindowState) -> UUID? {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            return profile.id
        }
        if let profileId = windowState.currentProfileId {
            return profileId
        }
        return browserManager?.currentProfile?.id
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID
    ) -> Bool {
        resolvedProfileId(for: windowState) == profileId
    }

    func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
    }

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = extensionControllersByProfile[profileId] {
            return existing
        }

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.setupExtensionController"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.setupExtensionController",
                signpostState
            )
        }

        let defaultDataStore = getExtensionDataStore(for: profileId)
        let controller = makeExtensionController(
            defaultDataStore: defaultDataStore,
            profileId: profileId
        )
        extensionControllersByProfile[profileId] = controller
        scheduleControllerDelegateRebind(for: controller)

        if currentProfileId == profileId {
            browserConfiguration.webViewConfiguration.webExtensionController = controller
        }

        extensionRuntimeTrace(
            "ensureExtensionController profile=\(profileId.uuidString) controller=\(extensionRuntimeControllerDescription(controller))"
        )
        updateWebViewsForProfile(profileId)
        verifyExtensionStorage(profileId: profileId)
        return controller
    }

    func extensionController(for tab: Tab) -> WKWebExtensionController? {
        guard let profileId = resolvedProfileId(for: tab) else { return nil }
        if let controller = extensionControllersByProfile[profileId] {
            return controller
        }
        guard hasEnabledInstalledExtensions else { return nil }
        return ensureExtensionController(for: profileId)
    }

    func getExtensionContext(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return nil }
        return extensionContexts(for: resolvedProfileId)[extensionId]
    }

    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        guard isExtensionSupportAvailable else { return }

        let controller = ensureExtensionController(for: profileId)
        let enabledEntities = enabledPersistedExtensionEntities()
        guard enabledEntities.isEmpty == false else { return }

        for entity in enabledEntities {
            guard getExtensionContext(for: entity.id, profileId: profileId) == nil else {
                continue
            }

            do {
                _ = try await loadEnabledExtension(
                    from: entity,
                    profileId: profileId,
                    expectedLoadGeneration: extensionLoadGeneration
                )
            } catch {
                Self.logger.error(
                    "Failed to load enabled extension \(entity.name, privacy: .public) for profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        _ = controller
    }

    func updateWebViewsForProfile(_ profileId: UUID) {
        guard let controller = extensionControllersByProfile[profileId] else { return }
        guard browserManager != nil else { return }

        for tab in allKnownTabs() {
            guard resolvedProfileId(for: tab) == profileId else { continue }
            for webView in liveWebViews(for: tab) {
                let existingController = webView.configuration.webExtensionController
                let canLateBind = canLateBindExtensionController(to: webView)
                let willAssign = existingController == nil && canLateBind
                extensionRuntimeTrace(
                    "updateWebViewsForProfile webView=\(extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(controller)) canLateBind=\(canLateBind) willAssign=\(willAssign) \(extensionRuntimeTabDescription(tab))"
                )
                if willAssign {
                    webView.configuration.webExtensionController = controller
                    webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                }
            }
        }
    }

    func refreshActionSurfaceStateForCurrentProfile() {
        guard let profileId = currentProfileId else { return }
        for (extensionId, context) in extensionContexts(for: profileId) {
            publishActionSurfaceStateForLoadedContext(context)
            _ = extensionId
        }
    }

    func backgroundScopedKey(
        extensionId: String,
        profileId: UUID
    ) -> String {
        "\(profileId.uuidString):\(extensionId)"
    }
}
