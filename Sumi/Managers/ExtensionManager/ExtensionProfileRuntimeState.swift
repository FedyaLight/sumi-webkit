import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionProfileRuntimeState {
    private(set) var controllersByProfile: [UUID: WKWebExtensionController] = [:]
    private(set) var contextsByProfile: [UUID: [String: WKWebExtensionContext]] = [:]
    private(set) var contextBindingGenerationByProfile: [UUID: UInt64] = [:]

    func controller(for profileId: UUID) -> WKWebExtensionController? {
        controllersByProfile[profileId]
    }

    mutating func setController(
        _ controller: WKWebExtensionController,
        for profileId: UUID
    ) {
        controllersByProfile[profileId] = controller
    }

    mutating func replaceControllers(
        _ controllers: [UUID: WKWebExtensionController]
    ) {
        controllersByProfile = controllers
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        contextsByProfile[profileId] ?? [:]
    }

    mutating func setContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) -> UInt64 {
        var contexts = contextsByProfile[profileId] ?? [:]
        contexts[extensionId] = context
        contextsByProfile[profileId] = contexts
        return bumpContextBindingGeneration(for: profileId)
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

        let generation = bumpContextBindingGeneration(for: profileId)
        return (removed, generation)
    }

    mutating func replaceContexts(
        _ contexts: [UUID: [String: WKWebExtensionContext]]
    ) {
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

    func allLoadedExtensionIDs() -> Set<String> {
        Set(contextsByProfile.values.flatMap(\.keys))
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        contextIdentity(for: extensionContext)?.profileId
    }

    func extensionId(for extensionContext: WKWebExtensionContext) -> String? {
        if let identity = contextIdentity(for: extensionContext) {
            return identity.extensionId
        }

        var webExtensionMatches = Set<String>()
        for contexts in contextsByProfile.values {
            for (extensionId, context) in contexts
            where context.webExtension === extensionContext.webExtension
            {
                webExtensionMatches.insert(extensionId)
            }
        }
        return webExtensionMatches.count == 1 ? webExtensionMatches.first : nil
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        for (profileId, contexts) in contextsByProfile {
            if let extensionId = contexts.first(where: { $0.value === extensionContext })?.key {
                return (extensionId, profileId)
            }
        }

        var baseURLMatches: [(extensionId: String, profileId: UUID)] = []
        for (profileId, contexts) in contextsByProfile {
            for (extensionId, context) in contexts
            where context.baseURL == extensionContext.baseURL
            {
                baseURLMatches.append((extensionId, profileId))
            }
        }
        if baseURLMatches.count == 1 {
            return baseURLMatches[0]
        }

        var webExtensionMatches: [(extensionId: String, profileId: UUID)] = []
        for (profileId, contexts) in contextsByProfile {
            for (extensionId, context) in contexts
            where context.webExtension === extensionContext.webExtension
            {
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
}
