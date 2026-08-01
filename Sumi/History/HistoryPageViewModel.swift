import AppKit
import Combine
import Foundation
import SumiDomain

@MainActor
struct HistoryPageBrowserContext {
    let historyManager: HistoryManager
    let faviconService: any BrowserFaviconServicing
    let faviconImageReader: any BrowserFaviconImageReading
    let currentProfile: () -> Profile?
    let currentProfileUpdates: AnyPublisher<Profile?, Never>
    let currentTab: (BrowserWindowState) -> Tab?
    let openHistoryURL: (URL, BrowserWindowState, HistoryOpenMode) -> Void
    let openHistoryURLsInNewTabs: ([URL], BrowserWindowState) -> Void
    let presentBrowsingDataSheet: (BrowserWindowState?) -> Void
    let scheduleRuntimeStatePersistence: (Tab) -> Void
    let sumiSettings: () -> SumiSettingsService?
}

@MainActor
final class HistoryPageViewModel: ObservableObject {
    var selectedRange: HistoryRange {
        didSet {
            guard selectedRange != oldValue else { return }
            syncSelectedRangeToActiveTab()
            scheduleSnapshotRebuild()
        }
    }
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSnapshotRebuild()
        }
    }
    @Published private(set) var sections: [HistorySection] = []
    private var isRefreshing = false
    private var isLoadingNextPage = false

    private weak var windowState: BrowserWindowState?
    private let browserContext: HistoryPageBrowserContext
    private let historyManager: HistoryManager
    private let faviconService: any BrowserFaviconServicing
    private let confirmDeletionOverride: (@MainActor (_ title: String, _ message: String) -> Bool)?
    private let calendar = Calendar.autoupdatingCurrent
    private let sectionDateFormatter: DateFormatter
    private var revisionCancellable: AnyCancellable?
    private var currentProfileCancellable: AnyCancellable?
    private var snapshotTask: Task<Void, Never>?
    private var snapshotGeneration: UInt64 = 0
    private var hasAppeared = false
    private var loadedItems: [HistoryListItem] = []
    private var nextPageOffset = 0
    private var hasMorePages = false
    private let pageSize = HistoryStore.defaultHistoryPageLimit

    init(
        browserContext: HistoryPageBrowserContext,
        windowState: BrowserWindowState?,
        confirmDeletion: (@MainActor (_ title: String, _ message: String) -> Bool)? = nil
    ) {
        self.windowState = windowState
        self.browserContext = browserContext
        self.historyManager = browserContext.historyManager
        self.faviconService = browserContext.faviconService
        self.confirmDeletionOverride = confirmDeletion
        let sectionDateFormatter = DateFormatter()
        sectionDateFormatter.locale = .autoupdatingCurrent
        sectionDateFormatter.calendar = calendar
        sectionDateFormatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d yyyy")
        self.sectionDateFormatter = sectionDateFormatter
        let activeHistoryURL = windowState.flatMap {
            browserContext.currentTab($0)?.url
        }
        self.selectedRange = activeHistoryURL
            .flatMap { SumiSurface.historyRangeQuery(from: $0) }
            .flatMap(HistoryRange.init(rawValue:))
            ?? .all

        revisionCancellable = historyManager.$revision
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRebuild()
                }
            }
        currentProfileCancellable = browserContext.currentProfileUpdates
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSnapshotRebuild()
            }
    }

    isolated deinit {
        snapshotTask?.cancel()
        revisionCancellable?.cancel()
        currentProfileCancellable?.cancel()
    }

    var faviconPartition: SumiFaviconPartition {
        faviconService.partition(profile: browserContext.currentProfile())
    }

    var faviconImageReader: any BrowserFaviconImageReading {
        browserContext.faviconImageReader
    }

    func appear() {
        guard hasAppeared == false else {
            scheduleSnapshotRebuild()
            return
        }
        hasAppeared = true
        scheduleSnapshotRebuild()
    }

    func open(_ item: HistoryListItem, mode: HistoryOpenMode) {
        guard let windowState else { return }
        browserContext.openHistoryURL(item.url, windowState, mode)
    }

    func openFromRow(
        _ item: HistoryListItem,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        let mode: HistoryOpenMode = modifiers.contains(.command)
            ? .newTab
            : .currentTab
        open(item, mode: mode)
    }

    func openInNewTabs(_ items: [HistoryListItem]) {
        guard let windowState else { return }
        let urls = items.map(\.url).uniquedPreservingOrder()
        browserContext.openHistoryURLsInNewTabs(urls, windowState)
    }

    func copyLink(_ item: HistoryListItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
    }

    func delete(_ item: HistoryListItem) {
        Task { [weak self] in
            await self?.deleteItem(item)
        }
    }

    func delete(_ items: [HistoryListItem]) {
        Task { [weak self] in
            await self?.deleteItems(items)
        }
    }

    func showBrowsingDataDialog() {
        browserContext.presentBrowsingDataSheet(windowState)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSnapshotRebuild() {
        snapshotGeneration &+= 1
        let generation = snapshotGeneration
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  Task.isCancelled == false,
                  generation == self.snapshotGeneration
            else { return }
            await self.reloadSnapshot(generation: generation)
        }
    }

    func loadNextPageIfNeeded(after item: HistoryListItem) {
        guard loadedItems.last?.id == item.id else { return }
        Task { [weak self] in
            await self?.loadNextPage()
        }
    }

    private func reloadSnapshot(generation: UInt64) async {
        isRefreshing = true
        isLoadingNextPage = false
        loadedItems = []
        nextPageOffset = 0
        hasMorePages = false
        let page = await historyManager.historyPage(
            query: currentQuery(),
            searchTerm: currentSearchTerm(),
            limit: pageSize,
            offset: 0
        )

        guard generation == snapshotGeneration,
              Task.isCancelled == false
        else {
            isRefreshing = false
            return
        }

        loadedItems = page.items
        nextPageOffset = page.nextOffset
        hasMorePages = page.hasMore
        sections = makeSections(from: loadedItems)
        isRefreshing = false
    }

    private func loadNextPage() async {
        guard hasMorePages,
              isRefreshing == false,
              isLoadingNextPage == false
        else { return }

        isLoadingNextPage = true
        let generation = snapshotGeneration
        let page = await historyManager.historyPage(
            query: currentQuery(),
            searchTerm: currentSearchTerm(),
            limit: pageSize,
            offset: nextPageOffset
        )

        guard generation == snapshotGeneration,
              Task.isCancelled == false
        else {
            isLoadingNextPage = false
            return
        }

        loadedItems.append(contentsOf: page.items)
        nextPageOffset = page.nextOffset
        hasMorePages = page.hasMore
        sections = makeSections(from: loadedItems)
        isLoadingNextPage = false
    }

    private func currentQuery() -> HistoryQuery {
        if selectedRange == .allSites {
            return .rangeFilter(.allSites)
        }
        if selectedRange != .all {
            return .rangeFilter(selectedRange)
        }
        return .rangeFilter(.all)
    }

    private func currentSearchTerm() -> String? {
        trimmedSearchText.isEmpty ? nil : trimmedSearchText
    }

    private func makeSections(from items: [HistoryListItem]) -> [HistorySection] {
        if selectedRange == .allSites {
            return [.init(id: "sites", title: HistoryRange.allSites.title, items: items)]
        }

        var order: [Date] = []
        var grouped: [Date: [HistoryListItem]] = [:]
        var undatedItems: [HistoryListItem] = []
        for item in items {
            guard let visitedAt = item.visitedAt else {
                undatedItems.append(item)
                continue
            }
            let day = calendar.startOfDay(for: visitedAt)
            if grouped[day] == nil {
                order.append(day)
            }
            grouped[day, default: []].append(item)
        }

        var sections = order.map { day in
            HistorySection(
                id: "day:\(day.timeIntervalSince1970)",
                title: sectionTitle(for: day),
                items: grouped[day] ?? []
            )
        }

        if !undatedItems.isEmpty {
            sections.append(.init(id: "history", title: "History", items: undatedItems))
        }
        return sections
    }

    private func sectionTitle(for day: Date) -> String {
        let referenceDate = Date()
        let fullDate = sectionDateFormatter.string(from: day)
        if calendar.isDate(day, inSameDayAs: referenceDate) {
            return String(localized: "Recently Visited Today")
        }
        return fullDate
    }

    private func syncSelectedRangeToActiveTab() {
        guard let tab = activeHistoryTab() else { return }
        let newURL = SumiSurface.historySurfaceURL(rangeQuery: selectedRange.paneQueryValue)
        guard tab.url != newURL else { return }
        tab.url = newURL
        tab.name = "History"
        tab.faviconPresentation = .systemSymbol(SumiSurface.historyTabFaviconSystemImageName)
        tab.faviconIsTemplateGlobePlaceholder = false
        browserContext.scheduleRuntimeStatePersistence(tab)
    }

    private func activeHistoryTab() -> Tab? {
        guard let windowState,
              let tab = browserContext.currentTab(windowState),
              tab.representsSumiHistorySurface
        else {
            return nil
        }
        return tab
    }

    private func deleteItem(_ item: HistoryListItem) async {
        if item.isSiteAggregate {
            guard confirmDeletion(
                title: "Delete Site History",
                message: "This will permanently remove all history entries for \(item.siteDomain ?? item.domain)."
            ) else { return }
            await historyManager.delete(query: .domainFilter([item.siteDomain ?? item.domain]))
            return
        }

        guard let visitID = item.visitID else { return }
        await historyManager.delete(query: .visits([visitID]))
    }

    private func deleteItems(_ selectedItems: [HistoryListItem]) async {
        guard !selectedItems.isEmpty else { return }

        let selectedDomains = Set(
            selectedItems
                .filter(\.isSiteAggregate)
                .map { $0.siteDomain ?? $0.domain }
        )
        let selectedVisitIDs = selectedItems
            .filter { !$0.isSiteAggregate }
            .compactMap(\.visitID)

        let requiresConfirmation = selectedItems.count > 1 || !selectedDomains.isEmpty
        if requiresConfirmation,
           !confirmDeletion(
            title: "Delete Selected History",
            message: "This will permanently remove the selected history entries."
           ) {
            return
        }

        await historyManager.deleteSelection(
            visitIDs: selectedVisitIDs,
            domains: selectedDomains
        )
    }

    private func confirmDeletion(title: String, message: String) -> Bool {
        if let confirmDeletionOverride {
            return confirmDeletionOverride(title, message)
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.sumiApplyNativeSurfaceAppearance(
            windowState: windowState,
            settings: browserContext.sumiSettings()
        )
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
