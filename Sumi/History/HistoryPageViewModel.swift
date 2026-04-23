import AppKit
import Combine
import Foundation

@MainActor
final class HistoryPageViewModel: ObservableObject {
    @Published var selectedRange: HistoryRange {
        didSet {
            guard selectedRange != oldValue else { return }
            domainFilter = nil
            syncSelectedRangeToActiveTab()
            scheduleSnapshotRebuild()
        }
    }
    @Published var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSnapshotRebuild()
        }
    }
    @Published private(set) var ranges: [HistoryRangeCount] = []
    @Published private(set) var sections: [HistorySection] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var domainFilter: String?
    @Published private(set) var selectedItemIDs: Set<String> = []

    private weak var browserManager: BrowserManager?
    private weak var windowState: BrowserWindowState?
    private let historyManager: HistoryManager
    private let confirmDeletion: @MainActor (_ title: String, _ message: String) -> Bool
    private var revisionCancellable: AnyCancellable?
    private var snapshotTask: Task<Void, Never>?
    private var snapshotGeneration: UInt64 = 0
    private var hasAppeared = false

    init(
        browserManager: BrowserManager,
        windowState: BrowserWindowState?,
        confirmDeletion: @escaping @MainActor (_ title: String, _ message: String) -> Bool = HistoryPageViewModel.showDeleteConfirmation
    ) {
        self.browserManager = browserManager
        self.windowState = windowState
        self.historyManager = browserManager.historyManager
        self.confirmDeletion = confirmDeletion
        let initialRange = windowState
            .flatMap { browserManager.currentTab(for: $0) }
            .flatMap { SumiSurface.historyRange(from: $0.url) } ?? .all
        self.selectedRange = initialRange

        revisionCancellable = historyManager.$revision
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleSnapshotRebuild()
                }
            }
    }

    deinit {
        snapshotTask?.cancel()
        revisionCancellable?.cancel()
    }

    var hasVisibleItems: Bool {
        sections.contains { !$0.items.isEmpty }
    }

    var canClearHistory: Bool {
        historyManager.canClearHistory
    }

    var selectionCount: Int {
        selectedItemIDs.count
    }

    var hasSelection: Bool {
        !selectedItemIDs.isEmpty
    }

    var canDeleteVisibleResults: Bool {
        guard hasVisibleItems else { return false }
        if domainFilter != nil { return true }
        if trimmedSearchText.isEmpty == false { return true }
        return selectedRange != .all && selectedRange != .allSites
    }

    var activeFilterDescription: String? {
        if let domainFilter {
            return "Site: \(domainFilter)"
        }
        if trimmedSearchText.isEmpty == false {
            return "Search: \(trimmedSearchText)"
        }
        return nil
    }

    func appear() {
        if let tab = activeHistoryTab(),
           let range = SumiSurface.historyRange(from: tab.url),
           range != selectedRange {
            selectedRange = range
        }

        guard hasAppeared == false else {
            scheduleSnapshotRebuild()
            return
        }
        hasAppeared = true
        scheduleSnapshotRebuild()
        Task { [weak self] in
            await self?.refreshFromStore()
        }
    }

    func selectRange(_ range: HistoryRange) {
        selectedRange = range
    }

    func clearFilters() {
        domainFilter = nil
        if searchText.isEmpty == false {
            searchText = ""
        } else {
            scheduleSnapshotRebuild()
        }
    }

    func showAllHistory(from item: HistoryListItem) {
        let domain = item.siteDomain ?? item.domain
        if selectedRange != .all {
            selectedRange = .all
        }
        domainFilter = domain
        scheduleSnapshotRebuild()
    }

    func open(_ item: HistoryListItem, mode: BrowserManager.HistoryOpenMode) {
        guard let browserManager,
              let windowState
        else { return }
        browserManager.openHistoryURL(item.url, in: windowState, preferredOpenMode: mode)
    }

    func openFromRow(
        _ item: HistoryListItem,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        let mode: BrowserManager.HistoryOpenMode = modifiers.contains(.command)
            ? .newTab
            : .currentTab
        open(item, mode: mode)
    }

    func isSelected(_ item: HistoryListItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggleSelection(_ item: HistoryListItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func openSelectedItems() {
        guard let browserManager,
              let windowState
        else { return }
        let urls = selectedVisibleItems().map(\.url)
        guard !urls.isEmpty else { return }
        browserManager.openHistoryURLsInNewTabs(urls, in: windowState)
    }

    func deleteSelectedItems() {
        Task { [weak self] in
            await self?.deleteSelectedItemsNow()
        }
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

    func deleteVisibleResults() {
        Task { [weak self] in
            await self?.deleteVisibleResultsNow()
        }
    }

    func clearAllHistory() {
        browserManager?.clearAllHistoryFromMenu()
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshFromStore() async {
        isRefreshing = true
        await historyManager.refresh()
        isRefreshing = false
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
            self.rebuildSnapshot()
        }
    }

    private func rebuildSnapshot() {
        ranges = historyManager.ranges()

        let baseQuery: HistoryQuery
        if let domainFilter {
            baseQuery = .domainFilter([domainFilter])
        } else {
            baseQuery = .rangeFilter(selectedRange)
        }

        let baseItems = historyManager.dataProvider.items(for: baseQuery)
        let visibleItems: [HistoryListItem]
        if trimmedSearchText.isEmpty {
            visibleItems = baseItems
        } else {
            visibleItems = baseItems.filter { $0.matches(trimmedSearchText) }
        }

        pruneSelection(toVisibleItems: visibleItems)
        sections = makeSections(from: visibleItems)
    }

    private func makeSections(from items: [HistoryListItem]) -> [HistorySection] {
        if selectedRange == .allSites, domainFilter == nil {
            return [.init(id: "sites", title: HistoryRange.allSites.title, items: items)]
        }

        var order: [String] = []
        var grouped: [String: [HistoryListItem]] = [:]
        for item in items {
            let title = item.relativeDay.isEmpty ? "History" : item.relativeDay
            if grouped[title] == nil {
                order.append(title)
            }
            grouped[title, default: []].append(item)
        }

        return order.map { title in
            .init(id: title, title: title, items: grouped[title] ?? [])
        }
    }

    private func syncSelectedRangeToActiveTab() {
        guard let tab = activeHistoryTab() else { return }
        let newURL = SumiSurface.historySurfaceURL(rangeQuery: selectedRange.paneQueryValue)
        guard tab.url != newURL else { return }
        tab.url = newURL
        tab.name = "History"
        tab.favicon = .init(systemName: SumiSurface.historyTabFaviconSystemImageName)
        tab.faviconIsTemplateGlobePlaceholder = false
        browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
    }

    private func activeHistoryTab() -> Tab? {
        guard let browserManager,
              let windowState,
              let tab = browserManager.currentTab(for: windowState),
              tab.representsSumiHistorySurface
        else {
            return nil
        }
        return tab
    }

    private func deleteItem(_ item: HistoryListItem) async {
        if item.isSiteAggregate {
            guard confirmDeletion(
                "Delete Site History",
                "This will permanently remove all history entries for \(item.siteDomain ?? item.domain)."
            ) else { return }
            await historyManager.delete(query: .domainFilter([item.siteDomain ?? item.domain]))
            return
        }

        guard let visitID = item.visitID else { return }
        await historyManager.delete(query: .visits([visitID]))
    }

    func deleteSelectedItemsNow() async {
        let selectedItems = selectedVisibleItems()
        guard !selectedItems.isEmpty else {
            clearSelection()
            return
        }

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
            "Delete Selected History",
            "This will permanently remove the selected history entries."
           )
        {
            return
        }

        await historyManager.deleteSelection(
            visitIDs: selectedVisitIDs,
            domains: selectedDomains
        )
        clearSelection()
    }

    private func deleteVisibleResultsNow() async {
        guard canDeleteVisibleResults,
              confirmDeletion(
                "Delete History Results",
                "This will permanently remove the visible history entries."
              )
        else { return }

        if let deleteQuery = deleteQueryForVisibleResults() {
            await historyManager.delete(query: deleteQuery)
        } else if selectedRange == .allSites, domainFilter == nil {
            let domains = Set(sections.flatMap(\.items).map { $0.siteDomain ?? $0.domain })
            await historyManager.delete(query: .domainFilter(domains))
        } else {
            let visitIDs = sections.flatMap(\.items).compactMap(\.visitID)
            await historyManager.delete(query: .visits(visitIDs))
        }
    }

    private func deleteQueryForVisibleResults() -> HistoryQuery? {
        if let domainFilter, trimmedSearchText.isEmpty {
            return .domainFilter([domainFilter])
        }
        if domainFilter == nil, trimmedSearchText.isEmpty == false {
            return .searchTerm(trimmedSearchText)
        }
        if domainFilter == nil, selectedRange != .all, selectedRange != .allSites {
            return .rangeFilter(selectedRange)
        }
        return nil
    }

    private func selectedVisibleItems() -> [HistoryListItem] {
        sections
            .flatMap(\.items)
            .filter { selectedItemIDs.contains($0.id) }
    }

    private func pruneSelection(toVisibleItems items: [HistoryListItem]) {
        guard !selectedItemIDs.isEmpty else { return }
        let visibleIDs = Set(items.map(\.id))
        let prunedIDs = selectedItemIDs.intersection(visibleIDs)
        if prunedIDs != selectedItemIDs {
            selectedItemIDs = prunedIDs
        }
    }

    private static func showDeleteConfirmation(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
