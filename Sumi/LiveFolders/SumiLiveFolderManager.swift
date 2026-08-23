import AppKit
import Combine
import Foundation
import WebKit

@MainActor
struct SumiLiveFolderItemTabRuntime {
    var reconcile: (SumiLiveFolderSource, [SumiLiveFolderItem]) -> [SumiLiveFolderItem]
    var remove: (SumiLiveFolderSource, [SumiLiveFolderItem]) -> Void
    var detach: (SumiLiveFolderItem, SumiLiveFolderSource) -> Bool
    var activate: (SumiLiveFolderItem, SumiLiveFolderSource, BrowserWindowState) -> Bool

    static let inactive = Self(
        reconcile: { _, items in items },
        remove: { _, _ in /* No-op. */ },
        detach: { _, _ in false },
        activate: { _, _, _ in false }
    )
}

@MainActor
struct SumiLiveFolderRuntime {
    struct SpaceContext {
        var profileId: UUID?
    }

    var spaceContext: (UUID) -> SpaceContext?
    var createLiveFolder: (UUID, String) -> UUID?
    var markFolderLive: (UUID) -> Void
    var updateFolderIcon: (UUID, String) -> Void
    var openNewTab: (String, BrowserWindowState, UUID?) -> Void
    var profile: (UUID?, UUID) -> Profile?
    var folderIds: () -> Set<UUID>
    var itemTabs: SumiLiveFolderItemTabRuntime

    static let inactive = Self(
        spaceContext: { _ in nil },
        createLiveFolder: { _, _ in nil },
        markFolderLive: { _ in /* No-op. */ },
        updateFolderIcon: { _, _ in /* No-op. */ },
        openNewTab: { _, _, _ in /* No-op. */ },
        profile: { _, _ in nil },
        folderIds: { [] },
        itemTabs: .inactive
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
    private var hasLoadedState = false
    private var pendingDeletedFolderIDs: Set<UUID> = []
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
                    let missingFolderIDs = Set(diskState.sources.map(\.folderId))
                        .subtracting(self.runtime.folderIds())
                    let deletedFolderIDs = missingFolderIDs
                        .union(self.pendingDeletedFolderIDs)
                    let restoredState = diskState.removingSources(
                        inFolderIDs: deletedFolderIDs
                    )
                    self.pendingDeletedFolderIDs.subtract(deletedFolderIDs)
                    self.apply(restoredState)
                    if restoredState != diskState {
                        self.persist()
                    }
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
        mutateContent(for: removedFolderIDs) {
            sourcesByFolderId = [:]
            itemsBySourceId = [:]
            dismissedItemIdsBySourceId = [:]
        }
        hasLoadedState = false
        runtime = .inactive
        hasAttachedRuntime = false
    }

    func source(for folderId: UUID) -> SumiLiveFolderSource? {
        sourcesByFolderId[folderId]
    }

    func visibleItems(for folderId: UUID) -> [SumiLiveFolderItem] {
        guard let source = sourcesByFolderId[folderId] else { return [] }
        let dismissed = dismissedItemIdsBySourceId[source.id] ?? []
        return (itemsBySourceId[source.id] ?? [])
            .filter { !dismissed.contains($0.id) }
    }

    /// Exact work-scoped invalidation for one rendered folder. Current content
    /// is read separately at demand time by the sidebar snapshot reader.
    func contentChanges(for folderId: UUID) -> AnyPublisher<Void, Never> {
        folderContentChanged
            .filter { $0 == folderId }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func createRSSFolder(in spaceId: UUID, feedURLString: String) async {
        guard runtime.spaceContext(spaceId) != nil,
              let feedURL = URL(string: feedURLString),
              ["http", "https"].contains(feedURL.scheme?.lowercased()) else {
            return
        }
        let cookies = await cookiesForSpace(spaceId)
        let metadataTitle = await SumiRSSLiveFolderProvider(networkClient: networkClient)
            .fetchMetadata(url: feedURL, cookies: cookies)
        guard !Task.isCancelled,
              runtime.spaceContext(spaceId) != nil,
              let folderId = runtime.createLiveFolder(
                  spaceId,
                  metadataTitle.flatMap { $0.isEmpty ? nil : $0 }
                      ?? SumiLiveFolderKind.rss.defaultFolderName
              ) else {
            return
        }
        runtime.updateFolderIcon(
            folderId,
            SumiZenFolderIconCatalog.storageValue(for: "logo-rss")
        )
        let source = SumiLiveFolderSource(
            folderId: folderId,
            spaceId: spaceId,
            kind: .rss,
            title: metadataTitle,
            urlString: feedURL.absoluteString
        )
        insert(source)
        refresh(folderId: folderId)
    }

    func createGitHubFolder(in spaceId: UUID, kind: SumiLiveFolderKind) {
        guard kind == .githubPullRequests || kind == .githubIssues,
              runtime.spaceContext(spaceId) != nil,
              let folderId = runtime.createLiveFolder(spaceId, kind.defaultFolderName) else {
            return
        }
        runtime.updateFolderIcon(
            folderId,
            SumiZenFolderIconCatalog.storageValue(for: "logo-github")
        )
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
        let lastFinishedAt = source.nextRefreshAfter.map {
            $0.addingTimeInterval(-source.refreshIntervalSeconds)
        }
        source.refreshIntervalSeconds = seconds
        source.nextRefreshAfter = lastFinishedAt?.addingTimeInterval(seconds)
        mutateContent(for: folderId) {
            sourcesByFolderId[folderId] = source
        }
        persist()
        rescheduleBackgroundActivity()
        refreshIfStale(folderId: folderId)
    }

    func replaceSourceAndRefresh(_ source: SumiLiveFolderSource) {
        mutateContent(for: source.folderId) {
            sourcesByFolderId[source.folderId] = source
        }
        persist()
        if let currentRefresh = refreshTasksBySourceId[source.id] {
            currentRefresh.cancel()
            Task { [weak self] in
                await currentRefresh.value
                self?.refresh(folderId: source.folderId)
            }
        } else {
            refresh(folderId: source.folderId)
        }
    }

    func deleteState(forFolderIds folderIds: Set<UUID>) {
        guard !folderIds.isEmpty else { return }
        let deletedSources = sourcesByFolderId.values.filter { folderIds.contains($0.folderId) }
        guard !deletedSources.isEmpty else {
            pendingDeletedFolderIDs.formUnion(folderIds)
            Task { [store] in
                do {
                    try await store.deleteSources(inFolderIDs: folderIds)
                } catch {
                    RuntimeDiagnostics.emit(
                        "[LiveFolders] Failed to delete durable state: \(error)"
                    )
                }
            }
            return
        }
        for source in deletedSources {
            runtime.itemTabs.remove(source, itemsBySourceId[source.id] ?? [])
        }
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
        if let source = sourcesByFolderId.values.first(where: { $0.id == item.sourceId }),
           runtime.itemTabs.activate(item, source, windowState) {
            return
        }
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
            response = await SumiRSSLiveFolderProvider(networkClient: networkClient).fetch(
                source: source,
                cookies: cookies
            )
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
            latestSource.githubDashboardMode = response.githubDashboardMode
                ?? latestSource.githubDashboardMode
            switch response.outcome {
            case .success(let items, _, let activeRepositories):
                let merged = SumiLiveFolderItemMerge.retainingExistingOrder(
                    items,
                    with: itemsBySourceId[source.id] ?? [],
                    at: now
                )
                let liveIds = Set(merged.map(\.id))
                // Zen retains dismissals across an empty result because an empty
                // page is often a transient auth or parser failure.
                if !liveIds.isEmpty {
                    dismissedItemIdsBySourceId[source.id]?.formIntersection(liveIds)
                }
                let dismissed = dismissedItemIdsBySourceId[source.id] ?? []
                let visible = merged.filter { !dismissed.contains($0.id) }
                let reconciled = runtime.itemTabs.reconcile(latestSource, visible)
                let reconciledByID = Dictionary(
                    uniqueKeysWithValues: reconciled.map { ($0.id, $0) }
                )
                itemsBySourceId[source.id] = merged.map { item in
                    reconciledByID[item.id] ?? item
                }
                latestSource.activeRepositories = activeRepositories
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
            case .failure(let errorKind):
                latestSource.markFailure(errorKind, at: now)
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
        if dueFolderIds.isEmpty {
            rescheduleBackgroundActivity()
        }
    }

    private func cookiesForSource(_ source: SumiLiveFolderSource) async -> [HTTPCookie] {
        await cookiesForSpace(source.spaceId)
    }

    private func cookiesForSpace(_ spaceID: UUID) async -> [HTTPCookie] {
        guard let profile = runtime.profile(nil, spaceID) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            profile.dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func apply(_ diskState: SumiLiveFolderDiskState) {
        let previousFolderIDs = Set(sourcesByFolderId.keys)
        let nextSources = Dictionary(
            uniqueKeysWithValues: diskState.sources.map { ($0.folderId, $0) }
        )
        for folderID in nextSources.keys {
            runtime.markFolderLive(folderID)
        }
        mutateContent(for: previousFolderIDs.union(nextSources.keys)) {
            sourcesByFolderId = nextSources
            itemsBySourceId = Dictionary(
                uniqueKeysWithValues: diskState.itemCaches.map { ($0.sourceId, $0.items) }
            )
            dismissedItemIdsBySourceId = Dictionary(
                uniqueKeysWithValues: diskState.dismissals.map { ($0.sourceId, Set($0.itemIds)) }
            )
            reconcileRestoredItemTabs()
        }
    }

    private func reconcileRestoredItemTabs() {
        for source in sourcesByFolderId.values {
            let items = itemsBySourceId[source.id] ?? []
            let dismissed = dismissedItemIdsBySourceId[source.id] ?? []
            let visible = items.filter { !dismissed.contains($0.id) }
            let reconciled = runtime.itemTabs.reconcile(source, visible)
            let reconciledByID = Dictionary(
                uniqueKeysWithValues: reconciled.map { ($0.id, $0) }
            )
            itemsBySourceId[source.id] = items.map { item in
                reconciledByID[item.id] ?? item
            }
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
            try await store.verifyDurableState()
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
        let interval = max(1, nextDate.timeIntervalSince(now))

        let scheduler = NSBackgroundActivityScheduler(
            identifier: "\(SumiAppIdentity.runtimeBundleIdentifier).live-folders.refresh"
        )
        scheduler.repeats = false
        scheduler.interval = interval
        scheduler.tolerance = min(interval * 0.25, 10 * 60)
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

extension SumiLiveFolderManager {
    func reconcileExternalMove(
        shortcutPinID: UUID,
        fromFolderID: UUID,
        toFolderID: UUID?,
        targetIndex: Int?
    ) {
        guard let source = sourcesByFolderId[fromFolderID],
              let item = itemsBySourceId[source.id]?.first(where: {
                  $0.shortcutPinId == shortcutPinID
              }) else { return }
        guard toFolderID == fromFolderID else {
            recordDismissal(of: item)
            return
        }
        guard let targetIndex else { return }
        reorderVisibleItem(item, in: source, to: targetIndex)
    }

    private func reorderVisibleItem(
        _ item: SumiLiveFolderItem,
        in source: SumiLiveFolderSource,
        to targetIndex: Int
    ) {
        guard let cachedItems = itemsBySourceId[source.id] else { return }
        let dismissed = dismissedItemIdsBySourceId[source.id] ?? []
        var visibleItems = cachedItems.filter { !dismissed.contains($0.id) }
        guard let sourceIndex = visibleItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        let movedItem = visibleItems.remove(at: sourceIndex)
        visibleItems.insert(
            movedItem,
            at: min(max(0, targetIndex), visibleItems.count)
        )
        var nextVisibleIndex = 0
        mutateContent(for: source.folderId) {
            itemsBySourceId[source.id] = cachedItems.map { cached in
                guard !dismissed.contains(cached.id) else { return cached }
                defer { nextVisibleIndex += 1 }
                return visibleItems[nextVisibleIndex]
            }
        }
        persist()
    }

    func dismiss(item: SumiLiveFolderItem) {
        if let source = sourcesByFolderId.values.first(where: { $0.id == item.sourceId }) {
            runtime.itemTabs.remove(source, [item])
        }
        recordDismissal(of: item)
    }

    func detach(item: SumiLiveFolderItem) {
        guard let source = sourcesByFolderId.values.first(where: { $0.id == item.sourceId }),
              runtime.itemTabs.detach(item, source) else {
            return
        }
        recordDismissal(of: item)
    }

    private func recordDismissal(of item: SumiLiveFolderItem) {
        guard dismissedItemIdsBySourceId[item.sourceId]?.contains(item.id) != true
            || itemsBySourceId[item.sourceId]?.contains(where: {
                $0.id == item.id && $0.shortcutPinId != nil
            }) == true else { return }
        var dismissed = dismissedItemIdsBySourceId[item.sourceId] ?? []
        dismissed.insert(item.id)
        if let folderID = sourcesByFolderId.values.first(where: { $0.id == item.sourceId })?.folderId {
            mutateContent(for: folderID) {
                dismissedItemIdsBySourceId[item.sourceId] = dismissed
                itemsBySourceId[item.sourceId] = itemsBySourceId[item.sourceId]?.map { cached in
                    guard cached.id == item.id else { return cached }
                    var detached = cached
                    detached.shortcutPinId = nil
                    return detached
                }
            }
        } else {
            dismissedItemIdsBySourceId[item.sourceId] = dismissed
        }
        persist()
    }
}
