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

    private let installedExtensions: InstalledExtensionCollection
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeIsEnabled: @MainActor () -> Bool
    private let contextLoad: ContextLoad
    private let backgroundState: BackgroundState
    private let wakeBackground: BackgroundWake
    private let logFailure: FailureLog
    private let runtimeTasks = ExtensionProfileRuntimeTaskOwner<Void>()

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
        await runtimeTasks.run(profileID: profileID) {
            [weak self] in
            guard let self else { return }
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
    }

    func cancelAll() {
        runtimeTasks.cancelAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            runtimeTasks.tasksForDrain()
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
}
