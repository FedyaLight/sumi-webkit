import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContentScriptContextPreparationOwner {
    typealias ContextQuery = @MainActor (String, UUID) -> WKWebExtensionContext?
    typealias ContextLoad = @MainActor (String, UUID) async throws -> Void
    typealias FailureLog = @MainActor (Error, String, UUID, String) -> Void

    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let installedExtensions: InstalledExtensionCollection
    private let runtimeIsEnabled: @MainActor () -> Bool
    private let context: ContextQuery
    private let load: ContextLoad
    private let logFailure: FailureLog
    private var tasksByProfile: [UUID: ScheduledTask] = [:]
    private var retiredTokens = Set<UUID>()
    private var finishedBeforeRegistrationTokens = Set<UUID>()

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeIsEnabled: @escaping @MainActor () -> Bool,
        context: @escaping ContextQuery,
        load: @escaping ContextLoad,
        logFailure: @escaping FailureLog
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeIsEnabled = runtimeIsEnabled
        self.context = context
        self.load = load
        self.logFailure = logFailure
    }

    func profileHasLoadedContexts(profileID: UUID) -> Bool {
        guard runtimeIsEnabled() else { return true }
        let records = contentScriptExtensions()
        guard records.isEmpty == false else { return true }
        return records.allSatisfy {
            context($0.id, profileID)?.isLoaded == true
        }
    }

    func profileNeedsLoad(profileID: UUID) -> Bool {
        profileHasLoadedContexts(profileID: profileID) == false
    }

    func ensureLoaded(profileID: UUID) async {
        guard runtimeIsEnabled(), profileNeedsLoad(profileID: profileID) else {
            return
        }
        if let scheduled = tasksByProfile[profileID] {
            await scheduled.task.value
            return
        }

        let token = UUID()
        let task = Self.runtimeTask { [weak self] in
            guard let self else { return }
            defer { self.finish(profileID: profileID, token: token) }
            for record in self.contentScriptExtensions() {
                guard Task.isCancelled == false else { return }
                do {
                    try await self.load(record.id, profileID)
                } catch {
                    self.logFailure(
                        error,
                        record.id,
                        profileID,
                        "preload content-script context"
                    )
                }
            }
        }
        tasksByProfile[profileID] = ScheduledTask(token: token, task: task)
        clearIfFinishedBeforeRegistration(profileID: profileID, token: token)
        await task.value
    }

    func cancelAll() {
        for scheduled in tasksByProfile.values {
            scheduled.task.cancel()
            retiredTokens.insert(scheduled.token)
        }
        tasksByProfile.removeAll()
        finishedBeforeRegistrationTokens.removeAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            tasksByProfile.values.map(\.task)
        }
    #endif

    private func finish(profileID: UUID, token: UUID) {
        var resolved = false
        if tasksByProfile[profileID]?.token == token {
            tasksByProfile.removeValue(forKey: profileID)
            resolved = true
        }
        if retiredTokens.remove(token) != nil { resolved = true }
        guard resolved == false else { return }
        finishedBeforeRegistrationTokens.insert(token)
    }

    private func clearIfFinishedBeforeRegistration(
        profileID: UUID,
        token: UUID
    ) {
        guard finishedBeforeRegistrationTokens.remove(token) != nil else {
            return
        }
        if tasksByProfile[profileID]?.token == token {
            tasksByProfile.removeValue(forKey: profileID)
        }
    }

    private func contentScriptExtensions() -> [InstalledExtension] {
        installedExtensions.records.filter {
            $0.isEnabled && $0.hasContentScripts
        }
    }

    nonisolated static func runtimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task.detached { await operation() }
    }
}
