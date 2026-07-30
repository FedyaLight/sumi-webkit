import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialDocumentNativeMessagingWarmupOwner {
    typealias ContextLoad = @MainActor (String, UUID) async throws
        -> WKWebExtensionContext?
    typealias BackgroundState = @MainActor (String, UUID) ->
        ExtensionManager.BackgroundRuntimeState
    typealias BackgroundWake = @MainActor (
        WKWebExtension,
        WKWebExtensionContext
    ) async throws -> Void
    typealias FailureLog = @MainActor (Error, String, UUID, String) -> Void

    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let installedExtensions: InstalledExtensionCollection
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeIsEnabled: @MainActor () -> Bool
    private let contextLoad: ContextLoad
    private let backgroundState: BackgroundState
    private let wakeBackground: BackgroundWake
    private let logFailure: FailureLog
    private var tasksByProfile: [UUID: ScheduledTask] = [:]
    private var retiredTokens = Set<UUID>()
    private var finishedBeforeRegistrationTokens = Set<UUID>()

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeCatalog: ExtensionRuntimeCatalog,
        runtimeIsEnabled: @escaping @MainActor () -> Bool,
        contextLoad: @escaping ContextLoad,
        backgroundState: @escaping BackgroundState,
        wakeBackground: @escaping BackgroundWake,
        logFailure: @escaping FailureLog
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeCatalog = runtimeCatalog
        self.runtimeIsEnabled = runtimeIsEnabled
        self.contextLoad = contextLoad
        self.backgroundState = backgroundState
        self.wakeBackground = wakeBackground
        self.logFailure = logFailure
    }

    func profileNeedsWarmup(profileID: UUID) -> Bool {
        warmupExtensions(profileID: profileID).isEmpty == false
    }

    func ensureLoaded(profileID: UUID) async {
        guard runtimeIsEnabled(), profileNeedsWarmup(profileID: profileID) else {
            return
        }
        if let scheduled = tasksByProfile[profileID] {
            await scheduled.task.value
            return
        }

        let token = UUID()
        let task = ExtensionContentScriptContextPreparationOwner.runtimeTask {
            [weak self] in
            guard let self else { return }
            defer { self.finish(profileID: profileID, token: token) }
            for record in self.warmupExtensions(profileID: profileID) {
                guard Task.isCancelled == false else { return }
                do {
                    guard let context = try await self.contextLoad(
                        record.id,
                        profileID
                    ) else { continue }
                    try await self.wakeBackground(
                        context.webExtension,
                        context
                    )
                } catch {
                    self.logFailure(
                        error,
                        record.id,
                        profileID,
                        "warm initial-document native messaging runtime"
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

    private func warmupExtensions(profileID: UUID) -> [InstalledExtension] {
        guard runtimeIsEnabled() else { return [] }
        return installedExtensions.enabledContentScriptRecords.filter {
            record in
            record.hasBackground
                && declaresNativeMessaging(record)
                && backgroundState(record.id, profileID) != .loaded
        }
    }

    private func declaresNativeMessaging(_ record: InstalledExtension) -> Bool {
        let manifest = runtimeCatalog.manifest(for: record.id) ?? record.manifest
        return (manifest["permissions"] as? [String] ?? [])
            .contains("nativeMessaging")
    }

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

    private func clearIfFinishedBeforeRegistration(profileID: UUID, token: UUID) {
        guard finishedBeforeRegistrationTokens.remove(token) != nil else { return }
        if tasksByProfile[profileID]?.token == token {
            tasksByProfile.removeValue(forKey: profileID)
        }
    }
}
