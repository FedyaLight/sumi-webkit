import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExtensionContextBindingReceipt: Hashable {
    let key: ExtensionRuntimeResidencyState.ScopedKey
    let contextIdentifier: ObjectIdentifier
    let bindingRevision: UInt64
    let controllerIdentifier: ObjectIdentifier?
    let controllerBindingRevision: UInt64
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionProfileRuntimeState {
    private(set) var controllersByProfile: [UUID: WKWebExtensionController] = [:]
    private var controllerBindingRevisionByProfile: [UUID: UInt64] = [:]
    private(set) var contextsByProfile: [UUID: [String: WKWebExtensionContext]] = [:]
    private(set) var contextBindingGenerationByProfile: [UUID: UInt64] = [:]
    private var contextBindingRevisionByProfile:
        [UUID: [String: UInt64]] = [:]

    func controller(for profileId: UUID) -> WKWebExtensionController? {
        controllersByProfile[profileId]
    }

    mutating func setController(
        _ controller: WKWebExtensionController,
        for profileId: UUID
    ) {
        controllersByProfile[profileId] = controller
        bumpControllerBindingRevision(for: profileId)
    }

    mutating func replaceControllers(
        _ controllers: [UUID: WKWebExtensionController]
    ) {
        let profileIDs = Set(controllersByProfile.keys).union(controllers.keys)
        for profileID in profileIDs
        where controllersByProfile[profileID] !== controllers[profileID] {
            bumpControllerBindingRevision(for: profileID)
        }
        controllersByProfile = controllers
    }

    func controllerBindingRevision(for profileId: UUID) -> UInt64 {
        controllerBindingRevisionByProfile[profileId] ?? 0
    }

    private mutating func bumpControllerBindingRevision(for profileId: UUID) {
        controllerBindingRevisionByProfile[profileId] =
            (controllerBindingRevisionByProfile[profileId] ?? 0) &+ 1
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        contextsByProfile[profileId] ?? [:]
    }

    func loadedExtensionStates(for profileId: UUID) -> [String: Bool] {
        contexts(for: profileId).mapValues(\.isLoaded)
    }

    mutating func setContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) -> ExtensionContextBindingReceipt {
        var contexts = contextsByProfile[profileId] ?? [:]
        contexts[extensionId] = context
        contextsByProfile[profileId] = contexts
        let bindingRevision = bumpContextBindingRevision(
            extensionId: extensionId,
            profileId: profileId
        )
        _ = bumpContextBindingGeneration(for: profileId)
        return ExtensionContextBindingReceipt(
            key: .init(profileId: profileId, extensionId: extensionId),
            contextIdentifier: ObjectIdentifier(context),
            bindingRevision: bindingRevision,
            controllerIdentifier: controllersByProfile[profileId].map(
                ObjectIdentifier.init
            ),
            controllerBindingRevision: controllerBindingRevision(
                for: profileId
            )
        )
    }

    mutating func removeContext(
        extensionId: String,
        profileId: UUID
    ) -> (context: WKWebExtensionContext, generation: UInt64)? {
        guard var contexts = contextsByProfile[profileId],
              let removed = contexts.removeValue(forKey: extensionId)
        else {
            return nil
        }

        if contexts.isEmpty {
            contextsByProfile.removeValue(forKey: profileId)
        } else {
            contextsByProfile[profileId] = contexts
        }

        _ = bumpContextBindingRevision(
            extensionId: extensionId,
            profileId: profileId
        )
        let generation = bumpContextBindingGeneration(for: profileId)
        return (removed, generation)
    }

    func contextBindingReceipt(
        extensionId: String,
        profileId: UUID
    ) -> ExtensionContextBindingReceipt? {
        guard let context = contextsByProfile[profileId]?[extensionId]
        else {
            return nil
        }

        return ExtensionContextBindingReceipt(
            key: .init(profileId: profileId, extensionId: extensionId),
            contextIdentifier: ObjectIdentifier(context),
            bindingRevision: contextBindingRevision(
                extensionId: extensionId,
                profileId: profileId
            ),
            controllerIdentifier: controllersByProfile[profileId].map(
                ObjectIdentifier.init
            ),
            controllerBindingRevision: controllerBindingRevision(
                for: profileId
            )
        )
    }

    func isCurrent(_ receipt: ExtensionContextBindingReceipt) -> Bool {
        guard let context = contextsByProfile[receipt.key.profileId]?[
            receipt.key.extensionId
        ] else {
            return false
        }

        return ObjectIdentifier(context) == receipt.contextIdentifier
            && contextBindingRevision(
                extensionId: receipt.key.extensionId,
                profileId: receipt.key.profileId
            ) == receipt.bindingRevision
            && controllersByProfile[receipt.key.profileId].map(
                ObjectIdentifier.init
            ) == receipt.controllerIdentifier
            && controllerBindingRevision(
                for: receipt.key.profileId
            ) == receipt.controllerBindingRevision
    }

    func context(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> WKWebExtensionContext? {
        guard isCurrent(receipt) else { return nil }
        return contextsByProfile[receipt.key.profileId]?[receipt.key.extensionId]
    }

    func controller(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> WKWebExtensionController? {
        guard isCurrent(receipt) else { return nil }
        return controllersByProfile[receipt.key.profileId]
    }

    mutating func removeContext(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> (context: WKWebExtensionContext, generation: UInt64)? {
        guard isCurrent(receipt) else { return nil }
        return removeContext(
            extensionId: receipt.key.extensionId,
            profileId: receipt.key.profileId
        )
    }

    mutating func replaceContexts(
        _ contexts: [UUID: [String: WKWebExtensionContext]]
    ) {
        let profileIDs = Set(contextsByProfile.keys).union(contexts.keys)
        for profileID in profileIDs {
            let previous = contextsByProfile[profileID] ?? [:]
            let replacement = contexts[profileID] ?? [:]
            let extensionIDs = Set(previous.keys).union(replacement.keys)
            var profileChanged = false
            for extensionID in extensionIDs
            where previous[extensionID] !== replacement[extensionID] {
                profileChanged = true
                _ = bumpContextBindingRevision(
                    extensionId: extensionID,
                    profileId: profileID
                )
            }
            if profileChanged {
                _ = bumpContextBindingGeneration(for: profileID)
            }
        }
        contextsByProfile = contexts
    }

    func contextBindingGeneration(for profileId: UUID) -> UInt64 {
        contextBindingGenerationByProfile[profileId] ?? 0
    }

    @discardableResult
    mutating func bumpContextBindingGeneration(for profileId: UUID) -> UInt64 {
        let next = (contextBindingGenerationByProfile[profileId] ?? 0) &+ 1
        contextBindingGenerationByProfile[profileId] = next
        return next
    }

    mutating func replaceContextBindingGenerations(
        _ generations: [UUID: UInt64]
    ) {
        contextBindingGenerationByProfile = generations
    }

    func contextBindingRevision(
        extensionId: String,
        profileId: UUID
    ) -> UInt64 {
        contextBindingRevisionByProfile[profileId]?[extensionId] ?? 0
    }

    @discardableResult
    private mutating func bumpContextBindingRevision(
        extensionId: String,
        profileId: UUID
    ) -> UInt64 {
        var revisions = contextBindingRevisionByProfile[profileId] ?? [:]
        let next = (revisions[extensionId] ?? 0) &+ 1
        revisions[extensionId] = next
        // Keep removed bindings as tombstones so remove/re-add cannot recreate
        // an earlier callback capability.
        contextBindingRevisionByProfile[profileId] = revisions
        return next
    }

    func allLoadedExtensionIDs() -> Set<String> {
        Set(contextsByProfile.values.flatMap(\.keys))
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        contextIdentity(for: extensionContext)?.profileId
    }

    func exactContextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        var match: (extensionId: String, profileId: UUID)?
        for (profileId, contexts) in contextsByProfile {
            for (extensionId, context) in contexts
            where context === extensionContext {
                guard match == nil else { return nil }
                match = (extensionId, profileId)
            }
        }
        return match
    }

    func extensionId(for extensionContext: WKWebExtensionContext) -> String? {
        if let identity = contextIdentity(for: extensionContext) {
            return identity.extensionId
        }

        var webExtensionMatches = Set<String>()
        for contexts in contextsByProfile.values {
            for (extensionId, context) in contexts
            where context.webExtension === extensionContext.webExtension {
                webExtensionMatches.insert(extensionId)
            }
        }
        return webExtensionMatches.count == 1 ? webExtensionMatches.first : nil
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        if let identity = exactContextIdentity(for: extensionContext) {
            return identity
        }

        var baseURLMatches: [(extensionId: String, profileId: UUID)] = []
        for (profileId, contexts) in contextsByProfile {
            for (extensionId, context) in contexts
            where context.baseURL == extensionContext.baseURL {
                baseURLMatches.append((extensionId, profileId))
            }
        }
        if baseURLMatches.count == 1 {
            return baseURLMatches[0]
        }

        var webExtensionMatches: [(extensionId: String, profileId: UUID)] = []
        for (profileId, contexts) in contextsByProfile {
            for (extensionId, context) in contexts
            where context.webExtension === extensionContext.webExtension {
                webExtensionMatches.append((extensionId, profileId))
            }
        }
        return webExtensionMatches.count == 1 ? webExtensionMatches[0] : nil
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        controllersByProfile.first(where: { $0.value === controller })?.key
    }

    func countLoadedExtensionContexts() -> Int {
        contextsByProfile.values.reduce(0) { $0 + $1.count }
    }

    func inactiveLoadedContextIdentities(
        keepingProfileId: UUID
    ) -> [(profileId: UUID, extensionId: String)] {
        contextsByProfile
            .filter { $0.key != keepingProfileId }
            .flatMap { profileId, contexts in
                contexts.keys.map { extensionId in
                    (profileId: profileId, extensionId: extensionId)
                }
            }
    }

    func readinessContext(
        for profileId: UUID,
        hasEnabledExtensionDemand: Bool,
        enabledExtensionIDs: Set<String>,
        globalRuntimeReady: Bool
    ) -> ExtensionRuntimeReadinessContext {
        ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: hasEnabledExtensionDemand,
            enabledExtensionIDs: enabledExtensionIDs,
            loadedExtensionStatesByID: loadedExtensionStates(for: profileId),
            controllerExists: controller(for: profileId) != nil,
            globalRuntimeReady: globalRuntimeReady
        )
    }
}
