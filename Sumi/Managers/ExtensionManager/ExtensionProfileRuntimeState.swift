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
        for (profileId, contexts) in contextsByProfile {
            if contexts.values.contains(where: { $0 === extensionContext }) {
                return profileId
            }
        }
        return nil
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        controllersByProfile.first(where: { $0.value === controller })?.key
    }

    func countLoadedExtensionContexts() -> Int {
        contextsByProfile.values.reduce(0) { $0 + $1.count }
    }
}
