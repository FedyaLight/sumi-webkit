import AppKit
import Combine
import Foundation
import SwiftUI

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
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var domainFilter: String?
    @Published private(set) var selectedItemIDs: Set<String> = []

    private weak var browserManager: BrowserManager?
    private weak var windowState: BrowserWindowState?
    private let historyManager: HistoryManager
    private let confirmDeletion: @MainActor (_ title: String, _ message: String) -> Bool
    private let calendar = Calendar.autoupdatingCurrent
    private let sectionDateFormatter: DateFormatter
    private var revisionCancellable: AnyCancellable?
    private var snapshotTask: Task<Void, Never>?
    private var snapshotGeneration: UInt64 = 0
    private var hasAppeared = false
    private var loadedItems: [HistoryListItem] = []
    private var nextPageOffset = 0
    private var hasMorePages = false
    private let pageSize = HistoryStore.defaultHistoryPageLimit

    init(
        browserManager: BrowserManager,
        windowState: BrowserWindowState?,
        confirmDeletion: @escaping @MainActor (_ title: String, _ message: String) -> Bool = HistoryPageViewModel.showDeleteConfirmation
    ) {
        self.browserManager = browserManager
        self.windowState = windowState
        self.historyManager = browserManager.historyManager
        self.confirmDeletion = confirmDeletion
        let sectionDateFormatter = DateFormatter()
        sectionDateFormatter.locale = Locale(identifier: "en_US")
        sectionDateFormatter.calendar = calendar
        sectionDateFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        self.sectionDateFormatter = sectionDateFormatter
        self.selectedRange = .all

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

    var selectionCount: Int {
        selectedItemIDs.count
    }

    var hasSelection: Bool {
        !selectedItemIDs.isEmpty
    }

    var allVisibleItemsSelected: Bool {
        guard !visibleItems.isEmpty else { return false }
        let visibleIDs = Set(visibleItems.map(\.id))
        return visibleIDs.isSubset(of: selectedItemIDs)
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
        guard hasAppeared == false else {
            scheduleSnapshotRebuild()
            return
        }
        hasAppeared = true
        scheduleSnapshotRebuild()
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

    func selectAllVisibleItems() {
        selectedItemIDs.formUnion(visibleItems.map(\.id))
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

    func showBrowsingDataDialog() {
        guard let browserManager else { return }
        browserManager.showDialog(
            SumiBrowsingDataDialog(browserManager: browserManager)
        )
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
        guard visibleItems.last?.id == item.id else { return }
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
        ranges = historyManager.ranges()

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
        pruneSelection(toVisibleItems: loadedItems)
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
        pruneSelection(toVisibleItems: loadedItems)
        sections = makeSections(from: loadedItems)
        isLoadingNextPage = false
    }

    private func currentQuery() -> HistoryQuery {
        if let domainFilter {
            return .domainFilter([domainFilter])
        }
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
        if selectedRange == .allSites, domainFilter == nil {
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
            return "Today - \(fullDate)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(day, inSameDayAs: yesterday)
        {
            return "Yesterday - \(fullDate)"
        }
        return fullDate
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

    private func selectedVisibleItems() -> [HistoryListItem] {
        visibleItems
            .filter { selectedItemIDs.contains($0.id) }
    }

    private var visibleItems: [HistoryListItem] {
        loadedItems
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
