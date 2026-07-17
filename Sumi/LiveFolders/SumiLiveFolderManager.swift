import AppKit
import Combine
import Foundation
import WebKit

@MainActor
struct SumiLiveFolderRuntime {
    struct SpaceContext {
        var profileId: UUID?
    }

    var spaceContext: (UUID) -> SpaceContext?
    var createFolder: (UUID, String) -> UUID?
    var updateFolderIcon: (UUID, String) -> Void
    var renameFolder: (UUID, String) -> Void
    var openNewTab: (String, BrowserWindowState, UUID?) -> Void
    var profile: (UUID?, UUID) -> Profile?
    var folderIds: () -> Set<UUID>

    static let inactive = Self(
        spaceContext: { _ in nil },
        createFolder: { _, _ in nil },
        updateFolderIcon: { _, _ in /* No-op. */ },
        renameFolder: { _, _ in /* No-op. */ },
        openNewTab: { _, _, _ in /* No-op. */ },
        profile: { _, _ in nil },
        folderIds: { [] }
    )
}

@MainActor
final class SumiLiveFolderManager: ObservableObject {
    @Published private(set) var sourcesByFolderId: [UUID: SumiLiveFolderSource] = [:]
    @Published private(set) var itemsBySourceId: [UUID: [SumiLiveFolderItem]] = [:]
    private let folderContentChanged = PassthroughSubject<UUID, Never>()

    private var runtime = SumiLiveFolderRuntime.inactive
    private let store: SumiLiveFolderStore
    private let networkClient: SumiLiveFolderNetworkClient
    private var dismissedItemIdsBySourceId: [UUID: Set<String>] = [:]
    private var refreshTasksBySourceId: [UUID: Task<Void, Never>] = [:]
    private var scheduler: NSBackgroundActivityScheduler?
    private var wakeObserverToken: NSObjectProtocol?
    private var appActiveObserverToken: NSObjectProtocol?
    private var hasLoadedState = false
    private let workspace: NSWorkspace

    init(
        store: SumiLiveFolderStore = SumiLiveFolderStore(),
        networkClient: SumiLiveFolderNetworkClient = SumiLiveFolderNetworkClient(),
        workspace: NSWorkspace = NSWorkspace()
    ) {
        self.store = store
        self.networkClient = networkClient
        self.workspace = workspace
    }

    isolated deinit {
        scheduler?.invalidate()
        if let wakeObserverToken {
            workspace.notificationCenter.removeObserver(wakeObserverToken)
        }
        if let appActiveObserverToken {
            NotificationCenter.default.removeObserver(appActiveObserverToken)
        }
    }

    private(set) var hasAttachedRuntime = false

    func attach(runtime: SumiLiveFolderRuntime) {
        self.runtime = runtime
        hasAttachedRuntime = true
    }

    /// Starts Live Folders after tab restore. No-op when the Live Folders module is disabled.
    func startAfterTabRestore(isEnabled: Bool = true) {
        guard isEnabled else { return }
        guard !hasLoadedState else { return }
        hasLoadedState = true

        Task { [store] in
            do {
                let diskState = try await store.load()
                await MainActor.run {
                    self.apply(diskState)
                    self.reconcileOrphanedSources()
                    self.rescheduleBackgroundActivity()
                    self.refreshDueSources(reason: "startup")
                }
            } catch {
                RuntimeDiagnostics.emit(
                    "[LiveFolders] Failed to load durable state: \(error)"
                )
            }
        }

        wakeObserverToken = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDueSources(reason: "wake")
            }
        }

        appActiveObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDueSources(reason: "active")
            }
        }
    }

    /// Stops background work and clears the attached runtime (W4/R9 disable path).
    func stopAndClearRuntime() {
        let removedFolderIDs = Set(sourcesByFolderId.keys)
        for task in refreshTasksBySourceId.values {
            task.cancel()
        }
        refreshTasksBySourceId.removeAll()
        scheduler?.invalidate()
        scheduler = nil
        if let wakeObserverToken {
            workspace.notificationCenter.removeObserver(wakeObserverToken)
            self.wakeObserverToken = nil
        }
        if let appActiveObserverToken {
            NotificationCenter.default.removeObserver(appActiveObserverToken)
            self.appActiveObserverToken = nil
        }
        mutateContent(for: removedFolderIDs) {
            sourcesByFolderId = [:]
            itemsBySourceId = [:]
            dismissedItemIdsBySourceId = [:]
        }
        hasLoadedState = false
        runtime = .inactive
        hasAttachedRuntime = false
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        sourcesByFolderId[folderId] != nil
    }

    func source(for folderId: UUID) -> SumiLiveFolderSource? {
        sourcesByFolderId[folderId]
    }

    func visibleItems(for folderId: UUID) -> [SumiLiveFolderItem] {
        guard let source = sourcesByFolderId[folderId] else { return [] }
        let dismissed = dismissedItemIdsBySourceId[source.id] ?? []
        return (itemsBySourceId[source.id] ?? [])
            .filter { !dismissed.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.sortKeyDate > rhs.sortKeyDate
            }
    }

    /// Exact work-scoped invalidation for one rendered folder. Current content
    /// is read separately at demand time by the sidebar snapshot reader.
    func contentChanges(for folderId: UUID) -> AnyPublisher<Void, Never> {
        folderContentChanged
            .filter { $0 == folderId }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func createRSSFolder(in spaceId: UUID, feedURLString: String) {
        guard runtime.spaceContext(spaceId) != nil,
              let folderId = runtime.createFolder(spaceId, SumiLiveFolderKind.rss.defaultFolderName) else {
            return
        }
        runtime.updateFolderIcon(folderId, "dot.radiowaves.left.and.right")
        var source = SumiLiveFolderSource(
            folderId: folderId,
            spaceId: spaceId,
            kind: .rss,
            urlString: feedURLString
        )
        source.markAttempt()
        insert(source)
        refresh(folderId: folderId)
    }

    func createGitHubFolder(in spaceId: UUID, kind: SumiLiveFolderKind) {
        guard kind == .githubPullRequests || kind == .githubIssues,
              runtime.spaceContext(spaceId) != nil,
              let folderId = runtime.createFolder(spaceId, kind.defaultFolderName) else {
            return
        }
        runtime.updateFolderIcon(folderId, "chevron.left.forwardslash.chevron.right")
        let source = SumiLiveFolderSource(
            folderId: folderId,
            spaceId: spaceId,
            kind: kind
        )
        insert(source)
        refresh(folderId: folderId)
    }

    func refreshIfStale(folderId: UUID) {
        guard let source = sourcesByFolderId[folderId],
              source.isDueForRefresh else {
            return
        }
        refresh(folderId: folderId)
    }

    func refresh(folderId: UUID) {
        guard let source = sourcesByFolderId[folderId],
              refreshTasksBySourceId[source.id] == nil else {
            return
        }

        refreshTasksBySourceId[source.id] = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(sourceId: source.id)
        }
    }

    func setRefreshInterval(folderId: UUID, seconds: TimeInterval) {
        guard seconds > 0,
              var source = sourcesByFolderId[folderId] else {
            return
        }
        source.refreshIntervalSeconds = seconds
        source.nextRefreshAfter = Date().addingTimeInterval(seconds)
        mutateContent(for: folderId) {
            sourcesByFolderId[folderId] = source
        }
        persist()
        rescheduleBackgroundActivity()
    }

    func dismiss(item: SumiLiveFolderItem) {
        var dismissed = dismissedItemIdsBySourceId[item.sourceId] ?? []
        dismissed.insert(item.id)
        if let folderID = sourcesByFolderId.values.first(where: { $0.id == item.sourceId })?.folderId {
            mutateContent(for: folderID) {
                dismissedItemIdsBySourceId[item.sourceId] = dismissed
            }
        } else {
            dismissedItemIdsBySourceId[item.sourceId] = dismissed
        }
        persist()
    }

    func deleteState(forFolderIds folderIds: Set<UUID>) {
        guard !folderIds.isEmpty else { return }
        let deletedSources = sourcesByFolderId.values.filter { folderIds.contains($0.folderId) }
        guard !deletedSources.isEmpty else { return }
        mutateContent(for: Set(deletedSources.map(\.folderId))) {
            for source in deletedSources {
                refreshTasksBySourceId[source.id]?.cancel()
                refreshTasksBySourceId[source.id] = nil
                itemsBySourceId[source.id] = nil
                dismissedItemIdsBySourceId[source.id] = nil
                sourcesByFolderId[source.folderId] = nil
            }
        }
        persist()
        rescheduleBackgroundActivity()
    }

    func open(item: SumiLiveFolderItem, in windowState: BrowserWindowState) {
        runtime.openNewTab(
            item.urlString,
            windowState,
            sourcesByFolderId.values.first(where: { $0.id == item.sourceId })?.spaceId
        )
    }

    private func insert(_ source: SumiLiveFolderSource) {
        mutateContent(for: source.folderId) {
            sourcesByFolderId[source.folderId] = source
            itemsBySourceId[source.id] = []
            dismissedItemIdsBySourceId[source.id] = []
        }
        persist()
        rescheduleBackgroundActivity()
    }

    private func performRefresh(sourceId: UUID) async {
        guard var source = sourcesByFolderId.values.first(where: { $0.id == sourceId }) else {
            refreshTasksBySourceId[sourceId] = nil
            return
        }

        source.markAttempt()
        mutateContent(for: source.folderId) {
            sourcesByFolderId[source.folderId] = source
        }

        let cookies = await cookiesForSource(source)
        let response: SumiLiveFolderProviderResponse
        switch source.kind {
        case .rss:
            response = await SumiRSSLiveFolderProvider(networkClient: networkClient).fetch(source: source)
        case .githubPullRequests, .githubIssues:
            response = await SumiGitHubLiveFolderProvider(networkClient: networkClient).fetch(
                source: source,
                cookies: cookies
            )
        }

        guard !Task.isCancelled else {
            refreshTasksBySourceId[sourceId] = nil
            return
        }

        apply(response, to: source)
        refreshTasksBySourceId[sourceId] = nil
        persist()
        rescheduleBackgroundActivity()
    }

    private func apply(
        _ response: SumiLiveFolderProviderResponse,
        to source: SumiLiveFolderSource
    ) {
        guard var latestSource = sourcesByFolderId[source.folderId] else { return }
        let now = Date()

        mutateContent(for: latestSource.folderId) {
            switch response.outcome {
            case .success(let items, let title, let activeRepositories):
                let previousItems = Dictionary(
                    uniqueKeysWithValues: (itemsBySourceId[source.id] ?? []).map { ($0.id, $0) }
                )
                let merged = items.map { item -> SumiLiveFolderItem in
                    var next = item
                    next.firstSeenAt = previousItems[item.id]?.firstSeenAt ?? now
                    next.lastSeenAt = now
                    return next
                }
                itemsBySourceId[source.id] = merged
                let liveIds = Set(merged.map(\.id))
                dismissedItemIdsBySourceId[source.id]?.formIntersection(liveIds)
                latestSource.activeRepositories = activeRepositories
                if let title, !title.isEmpty, latestSource.kind == .rss {
                    latestSource.title = title
                    runtime.renameFolder(latestSource.folderId, title)
                }
                latestSource.markSuccess(
                    at: now,
                    etag: response.etag,
                    lastModified: response.lastModified
                )
            case .notModified:
                latestSource.markSuccess(
                    at: now,
                    etag: response.etag,
                    lastModified: response.lastModified
                )
            case .failure(let errorKind, let retryAfter):
                latestSource.markFailure(errorKind, retryAfter: retryAfter, at: now)
            }

            sourcesByFolderId[latestSource.folderId] = latestSource
        }
    }

    private func refreshDueSources(reason _: String) {
        let dueFolderIds = sourcesByFolderId.values
            .filter(\.isDueForRefresh)
            .map(\.folderId)
        for folderId in dueFolderIds {
            refresh(folderId: folderId)
        }
    }

    private func cookiesForSource(_ source: SumiLiveFolderSource) async -> [HTTPCookie] {
        guard source.kind == .githubPullRequests || source.kind == .githubIssues,
              let profile = profile(for: source) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            profile.dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func profile(for source: SumiLiveFolderSource) -> Profile? {
        runtime.profile(nil, source.spaceId)
    }

    private func apply(_ diskState: SumiLiveFolderDiskState) {
        let previousFolderIDs = Set(sourcesByFolderId.keys)
        let nextSources = Dictionary(
            uniqueKeysWithValues: diskState.sources.map { ($0.folderId, $0) }
        )
        mutateContent(for: previousFolderIDs.union(nextSources.keys)) {
            sourcesByFolderId = nextSources
            itemsBySourceId = Dictionary(
                uniqueKeysWithValues: diskState.itemCaches.map { ($0.sourceId, $0.items) }
            )
            dismissedItemIdsBySourceId = Dictionary(
                uniqueKeysWithValues: diskState.dismissals.map { ($0.sourceId, Set($0.itemIds)) }
            )
        }
    }

    private func mutateContent(
        for folderID: UUID,
        _ mutation: () -> Void
    ) {
        mutateContent(for: [folderID], mutation)
    }

    private func mutateContent(
        for folderIDs: Set<UUID>,
        _ mutation: () -> Void
    ) {
        mutation()
        for folderID in folderIDs {
            folderContentChanged.send(folderID)
        }
    }

    private func reconcileOrphanedSources() {
        let liveFolderIds = runtime.folderIds()
        let orphanedFolderIds = Set(sourcesByFolderId.keys).subtracting(liveFolderIds)
        deleteState(forFolderIds: orphanedFolderIds)
    }

    private func persist() {
        let state = SumiLiveFolderDiskState(
            sources: sourcesByFolderId.values.sorted { $0.folderId.uuidString < $1.folderId.uuidString },
            itemCaches: itemsBySourceId.keys.sorted { $0.uuidString < $1.uuidString }.map { sourceId in
                SumiLiveFolderItemCache(sourceId: sourceId, items: itemsBySourceId[sourceId] ?? [])
            },
            dismissals: dismissedItemIdsBySourceId.keys.sorted { $0.uuidString < $1.uuidString }.map { sourceId in
                SumiLiveFolderDismissalCache(
                    sourceId: sourceId,
                    itemIds: Array(dismissedItemIdsBySourceId[sourceId] ?? []).sorted()
                )
            }
        )
        Task { [store] in
            do {
                try await store.save(state)
            } catch {
                RuntimeDiagnostics.emit(
                    "[LiveFolders] Failed to persist durable state: \(error)"
                )
            }
        }
    }

    func prepareForProfileRetirement() async -> Bool {
        let tasks = Array(refreshTasksBySourceId.values)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            await task.value
        }
        refreshTasksBySourceId.removeAll()
        do {
            try await store.normalizeLegacyProfileReferences()
            return true
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Live Folder normalization failed: \(error)"
            )
            return false
        }
    }

    private func rescheduleBackgroundActivity() {
        scheduler?.invalidate()
        scheduler = nil

        let enabledSources = sourcesByFolderId.values.filter(\.isEnabled)
        guard !enabledSources.isEmpty else { return }

        let now = Date()
        let nextDate = enabledSources
            .map { $0.nextRefreshAfter ?? now }
            .min() ?? now.addingTimeInterval(30 * 60)
        let interval = max(10 * 60, nextDate.timeIntervalSince(now))

        let scheduler = NSBackgroundActivityScheduler(
            identifier: "\(SumiAppIdentity.runtimeBundleIdentifier).live-folders.refresh"
        )
        scheduler.repeats = false
        scheduler.interval = interval
        scheduler.tolerance = max(60, min(interval * 0.25, 10 * 60))
        scheduler.qualityOfService = .background
        scheduler.schedule { [weak self] completion in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion(.finished)
                    return
                }
                if self.scheduler?.shouldDefer == true {
                    self.rescheduleBackgroundActivity()
                    completion(.deferred)
                    return
                }
                self.refreshDueSources(reason: "background-scheduler")
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }
}
