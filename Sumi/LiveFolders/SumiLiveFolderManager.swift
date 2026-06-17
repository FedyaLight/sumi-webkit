import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class SumiLiveFolderManager: ObservableObject {
    @Published private(set) var sourcesByFolderId: [UUID: SumiLiveFolderSource] = [:]
    @Published private(set) var itemsBySourceId: [UUID: [SumiLiveFolderItem]] = [:]

    private weak var browserManager: BrowserManager?
    private let store: SumiLiveFolderStore
    private let networkClient: SumiLiveFolderNetworkClient
    private var dismissedItemIdsBySourceId: [UUID: Set<String>] = [:]
    private var refreshTasksBySourceId: [UUID: Task<Void, Never>] = [:]
    private var scheduler: NSBackgroundActivityScheduler?
    private var wakeObserverToken: NSObjectProtocol?
    private var appActiveObserverToken: NSObjectProtocol?
    private var hasLoadedState = false

    init(
        store: SumiLiveFolderStore = SumiLiveFolderStore(),
        networkClient: SumiLiveFolderNetworkClient = SumiLiveFolderNetworkClient()
    ) {
        self.store = store
        self.networkClient = networkClient
    }

    isolated deinit {
        scheduler?.invalidate()
        if let wakeObserverToken {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserverToken)
        }
        if let appActiveObserverToken {
            NotificationCenter.default.removeObserver(appActiveObserverToken)
        }
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func startAfterTabRestore() {
        guard !hasLoadedState else { return }
        hasLoadedState = true

        Task { [store] in
            let diskState = await store.load()
            await MainActor.run {
                self.apply(diskState)
                self.reconcileOrphanedSources()
                self.rescheduleBackgroundActivity()
                self.refreshDueSources(reason: "startup")
            }
        }

        wakeObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
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

    func createRSSFolder(in spaceId: UUID, feedURLString: String) {
        guard let browserManager,
              let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) else {
            return
        }
        let folder = browserManager.tabManager.createFolder(for: spaceId, name: SumiLiveFolderKind.rss.defaultFolderName)
        browserManager.tabManager.updateFolderIcon(folder.id, icon: "dot.radiowaves.left.and.right")
        var source = SumiLiveFolderSource(
            folderId: folder.id,
            spaceId: spaceId,
            profileId: space.profileId,
            kind: .rss,
            urlString: feedURLString
        )
        source.markAttempt()
        insert(source)
        refresh(folderId: folder.id)
    }

    func createGitHubFolder(in spaceId: UUID, kind: SumiLiveFolderKind) {
        guard kind == .githubPullRequests || kind == .githubIssues,
              let browserManager,
              let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) else {
            return
        }
        let folder = browserManager.tabManager.createFolder(for: spaceId, name: kind.defaultFolderName)
        browserManager.tabManager.updateFolderIcon(folder.id, icon: "chevron.left.forwardslash.chevron.right")
        let source = SumiLiveFolderSource(
            folderId: folder.id,
            spaceId: spaceId,
            profileId: space.profileId,
            kind: kind
        )
        insert(source)
        refresh(folderId: folder.id)
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
        sourcesByFolderId[folderId] = source
        persist()
        rescheduleBackgroundActivity()
    }

    func dismiss(item: SumiLiveFolderItem) {
        var dismissed = dismissedItemIdsBySourceId[item.sourceId] ?? []
        dismissed.insert(item.id)
        dismissedItemIdsBySourceId[item.sourceId] = dismissed
        persist()
    }

    func deleteState(forFolderIds folderIds: Set<UUID>) {
        guard !folderIds.isEmpty else { return }
        let deletedSources = sourcesByFolderId.values.filter { folderIds.contains($0.folderId) }
        guard !deletedSources.isEmpty else { return }
        for source in deletedSources {
            refreshTasksBySourceId[source.id]?.cancel()
            refreshTasksBySourceId[source.id] = nil
            itemsBySourceId[source.id] = nil
            dismissedItemIdsBySourceId[source.id] = nil
            sourcesByFolderId[source.folderId] = nil
        }
        persist()
        rescheduleBackgroundActivity()
    }

    func open(item: SumiLiveFolderItem, in windowState: BrowserWindowState) {
        browserManager?.openNewTab(
            url: item.urlString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: sourcesByFolderId.values.first(where: { $0.id == item.sourceId })?.spaceId
            )
        )
    }

    private func insert(_ source: SumiLiveFolderSource) {
        sourcesByFolderId[source.folderId] = source
        itemsBySourceId[source.id] = []
        dismissedItemIdsBySourceId[source.id] = []
        persist()
        rescheduleBackgroundActivity()
    }

    private func performRefresh(sourceId: UUID) async {
        guard var source = sourcesByFolderId.values.first(where: { $0.id == sourceId }) else {
            refreshTasksBySourceId[sourceId] = nil
            return
        }

        source.markAttempt()
        sourcesByFolderId[source.folderId] = source

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
                browserManager?.tabManager.renameFolder(latestSource.folderId, newName: title)
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

    private func refreshDueSources(reason: String) {
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
        if let profileId = source.profileId,
           let profile = browserManager?.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile
        }
        if let space = browserManager?.tabManager.spaces.first(where: { $0.id == source.spaceId }),
           let profileId = space.profileId {
            return browserManager?.profileManager.profiles.first(where: { $0.id == profileId })
        }
        return browserManager?.currentProfile
    }

    private func apply(_ diskState: SumiLiveFolderDiskState) {
        sourcesByFolderId = Dictionary(
            uniqueKeysWithValues: diskState.sources.map { ($0.folderId, $0) }
        )
        itemsBySourceId = Dictionary(
            uniqueKeysWithValues: diskState.itemCaches.map { ($0.sourceId, $0.items) }
        )
        dismissedItemIdsBySourceId = Dictionary(
            uniqueKeysWithValues: diskState.dismissals.map { ($0.sourceId, Set($0.itemIds)) }
        )
    }

    private func reconcileOrphanedSources() {
        guard let tabManager = browserManager?.tabManager else { return }
        let liveFolderIds = Set(tabManager.foldersBySpace.values.flatMap { folders in
            folders.map(\.id)
        })
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
            await store.save(state)
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
