import AppKit
import Combine
import SwiftUI

/// SwiftUI owns the browser-surface slot; the complete history presentation is
/// AppKit so scrolling, selection, keyboard commands, and menus stay native.
struct SumiHistoryTabRootView: NSViewControllerRepresentable {
    @Environment(\.resolvedThemeContext) private var themeContext

    let browserContext: HistoryPageBrowserContext
    let windowState: BrowserWindowState?

    func makeNSViewController(context _: Context) -> SumiHistoryViewController {
        let controller = SumiHistoryViewController(
            viewModel: HistoryPageViewModel(
                browserContext: browserContext,
                windowState: windowState
            )
        )
        controller.applyAppearance(themeContext.nativeSurfaceThemeContext)
        return controller
    }

    func updateNSViewController(
        _ controller: SumiHistoryViewController,
        context _: Context
    ) {
        controller.applyAppearance(themeContext.nativeSurfaceThemeContext)
    }
}

@MainActor
final class SumiHistoryViewController: NSViewController {
    private enum Layout {
        static let headerHeight: CGFloat = 45
        static let horizontalInset: CGFloat = 8
        static let tableHorizontalInset: CGFloat = 12
        static let searchWidth: CGFloat = 110
        static let firstColumnFraction: CGFloat = 0.31
        static let rowHeight: CGFloat = 20
    }

    private final class Node: NSObject {
        enum Content {
            case section(HistorySection)
            case item(HistoryListItem)
        }

        let id: String
        let content: Content
        var children: [Node]

        init(section: HistorySection) {
            id = section.id
            content = .section(section)
            children = section.items.map(Node.init(item:))
        }

        init(item: HistoryListItem) {
            id = item.id
            content = .item(item)
            children = []
        }
    }

    private let viewModel: HistoryPageViewModel
    private let outlineView = SumiHistoryOutlineView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let clearHistoryButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No History"))
    private var roots: [Node] = []
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var didApplyInitialSnapshot = false

    init(viewModel: HistoryPageViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        searchTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        configureHeader()
        configureOutlineView()
        configureEmptyState()
        installLayout()
        bindViewModel()
        viewModel.appear()
    }

    func applyAppearance(_ themeContext: ResolvedThemeContext) {
        view.sumiApplyNativeSurfaceAppearance(themeContext: themeContext)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let availableWidth = outlineView.bounds.width
        guard availableWidth > 0,
              let firstColumn = outlineView.tableColumns.first,
              let addressColumn = outlineView.tableColumns.last,
              firstColumn !== addressColumn
        else { return }
        let firstWidth = max(
            firstColumn.minWidth,
            floor(availableWidth * Layout.firstColumnFraction)
        )
        let addressWidth = max(addressColumn.minWidth, availableWidth - firstWidth)
        if abs(firstColumn.width - firstWidth) > 0.5 {
            firstColumn.width = firstWidth
        }
        if abs(addressColumn.width - addressWidth) > 0.5 {
            addressColumn.width = addressWidth
        }
    }

    private func configureHeader() {
        titleLabel.stringValue = String(localized: "History")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        clearHistoryButton.title = String(localized: "Clear History…")
        clearHistoryButton.bezelStyle = .rounded
        clearHistoryButton.controlSize = .small
        clearHistoryButton.target = self
        clearHistoryButton.action = #selector(showBrowsingData)
        clearHistoryButton.toolTip = String(localized: "Open Browsing Data")

        searchField.placeholderString = String(localized: "Search")
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.setContentHuggingPriority(.required, for: .horizontal)
        searchField.widthAnchor.constraint(equalToConstant: Layout.searchWidth).isActive = true

        let spacer = NSView()
        let header = NSStackView(views: [titleLabel, spacer, clearHistoryButton, searchField])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Layout.horizontalInset,
            bottom: 0,
            right: Layout.horizontalInset
        )
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Layout.headerHeight),
        ])
    }

    private func configureOutlineView() {
        let siteColumn = NSTableColumn(identifier: .historySite)
        siteColumn.title = String(localized: "Site")
        siteColumn.minWidth = 220
        siteColumn.width = 360

        let addressColumn = NSTableColumn(identifier: .historyAddress)
        addressColumn.title = String(localized: "Address")
        addressColumn.minWidth = 240
        addressColumn.resizingMask = .autoresizingMask

        outlineView.addTableColumn(siteColumn)
        outlineView.addTableColumn(addressColumn)
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.outlineTableColumn = siteColumn
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = Layout.rowHeight
        outlineView.rowSizeStyle = .small
        outlineView.intercellSpacing = .zero
        outlineView.indentationPerLevel = 14
        outlineView.gridStyleMask = .solidVerticalGridLineMask
        outlineView.gridColor = .separatorColor
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .clear
        outlineView.style = .plain
        outlineView.target = self
        outlineView.doubleAction = #selector(openSelectedRows)
        outlineView.onDelete = { [weak self] in self?.deleteSelectedRows() }
        outlineView.onReturn = { [weak self] in self?.openSelectedRows() }

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func configureEmptyState() {
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
    }

    private func installLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.headerHeight),
            scrollView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: Layout.tableHorizontalInset
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -Layout.tableHorizontalInset
            ),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    private func bindViewModel() {
        viewModel.$sections
            .sink { [weak self] sections in
                self?.apply(sections)
            }
            .store(in: &cancellables)

    }

    private func apply(_ sections: [HistorySection]) {
        let selectedIDs = selectedItems.map(\.id)
        let expandedIDs = roots.filter { outlineView.isItemExpanded($0) }.map(\.id)
        roots = sections.map(Node.init(section:))
        outlineView.reloadData()

        if didApplyInitialSnapshot {
            for root in roots where expandedIDs.contains(root.id) {
                outlineView.expandItem(root)
            }
        } else if let firstRoot = roots.first {
            outlineView.expandItem(firstRoot)
            didApplyInitialSnapshot = true
        }
        restoreSelection(ids: selectedIDs)
        emptyLabel.stringValue = viewModel.searchText.isEmpty
            ? String(localized: "No History")
            : String(localized: "No Matching History")
        emptyLabel.isHidden = sections.contains { !$0.items.isEmpty }
    }

    private func restoreSelection(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let rows = IndexSet((0..<outlineView.numberOfRows).filter { row in
            guard let node = outlineView.item(atRow: row) as? Node else { return false }
            return idSet.contains(node.id)
        })
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
    }

    private var selectedItems: [HistoryListItem] {
        outlineView.selectedRowIndexes.compactMap { row in
            guard let node = outlineView.item(atRow: row) as? Node,
                  case .item(let item) = node.content
            else { return nil }
            return item
        }
    }

    private func contextItem() -> HistoryListItem? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? Node,
              case .item(let item) = node.content
        else { return nil }
        return item
    }

    @objc private func showBrowsingData() {
        viewModel.showBrowsingDataDialog()
    }

    @objc private func openSelectedRows() {
        let items = selectedItems
        guard let item = items.first else { return }
        if items.count > 1 {
            viewModel.openInNewTabs(items)
        } else {
            viewModel.openFromRow(item, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
        }
    }

    @objc private func openContextItemInNewTab() {
        viewModel.openInNewTabs(contextSelectionItems)
    }

    @objc private func openContextItemInNewWindow() {
        guard let item = contextItem() else { return }
        viewModel.open(item, mode: .newWindow)
    }

    @objc private func copyContextItemLink() {
        guard let item = contextItem() else { return }
        viewModel.copyLink(item)
    }

    @objc private func deleteContextItem() {
        viewModel.delete(contextSelectionItems)
    }

    private func deleteSelectedRows() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        viewModel.delete(items)
    }

    private var contextSelectionItems: [HistoryListItem] {
        guard let item = contextItem() else { return [] }
        let selection = selectedItems
        return selection.contains(where: { $0.id == item.id }) ? selection : [item]
    }
}

extension SumiHistoryViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return !node.children.isEmpty
    }
}

extension SumiHistoryViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = SumiOutlineRowView()
        let level = outlineView.level(forItem: item)
        row.separatorLeadingInset = level > 0
            ? CGFloat(level) * outlineView.indentationPerLevel + 20
            : 0
        return row
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? Node else { return nil }
        switch node.content {
        case .section(let section):
            if tableColumn?.identifier == .historyAddress {
                let cell = reusableTextCell(in: outlineView, identifier: .historySectionCount)
                cell.textField?.stringValue = String(localized: "\(section.items.count) items")
                cell.textField?.font = .systemFont(ofSize: 12)
                cell.textField?.textColor = .labelColor
                return cell
            }
            let cell = reusableSectionCell(in: outlineView)
            cell.configure(title: section.title)
            return cell
        case .item(let historyItem):
            if tableColumn?.identifier == .historyAddress {
                let cell = reusableTextCell(in: outlineView, identifier: .historyAddressCell)
                cell.textField?.stringValue = historyItem.displayURL
                cell.textField?.lineBreakMode = .byTruncatingMiddle
                cell.toolTip = historyItem.displayURL
                return cell
            }
            let cell = reusableFaviconCell(in: outlineView)
            cell.configure(
                item: historyItem,
                partition: viewModel.faviconPartition,
                imageReader: viewModel.faviconImageReader
            )
            viewModel.loadNextPageIfNeeded(after: historyItem)
            return cell
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is Node
    }

    private func reusableTextCell(
        in outlineView: NSOutlineView,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTableCellView {
        if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func reusableFaviconCell(in outlineView: NSOutlineView) -> SumiHistoryFaviconCellView {
        if let cell = outlineView.makeView(withIdentifier: .historySiteCell, owner: self)
            as? SumiHistoryFaviconCellView {
            return cell
        }
        let cell = SumiHistoryFaviconCellView()
        cell.identifier = .historySiteCell
        return cell
    }

    private func reusableSectionCell(in outlineView: NSOutlineView) -> SumiHistorySectionCellView {
        if let cell = outlineView.makeView(withIdentifier: .historySection, owner: self)
            as? SumiHistorySectionCellView {
            return cell
        }
        let cell = SumiHistorySectionCellView()
        cell.identifier = .historySection
        return cell
    }
}

extension SumiHistoryViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        let query = searchField.stringValue
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.viewModel.searchText = query
        }
    }
}

extension SumiHistoryViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard contextItem() != nil else { return }
        let selectionCount = contextSelectionItems.count
        menu.addItem(
            withTitle: selectionCount > 1
                ? String(localized: "Open in New Tabs")
                : String(localized: "Open in New Tab"),
            action: #selector(openContextItemInNewTab),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "Open in New Window"),
            action: #selector(openContextItemInNewWindow),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: String(localized: "Copy"),
            action: #selector(copyContextItemLink),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: selectionCount > 1
                ? String(localized: "Delete Selected History")
                : String(localized: "Delete"),
            action: #selector(deleteContextItem),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }
    }
}

@MainActor
private final class SumiHistoryOutlineView: NSOutlineView {
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onReturn?()
        case 51, 117:
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let historySite = Self("HistorySite")
    static let historyAddress = Self("HistoryAddress")
    static let historySection = Self("HistorySection")
    static let historySectionCount = Self("HistorySectionCount")
    static let historySiteCell = Self("HistorySiteCell")
    static let historyAddressCell = Self("HistoryAddressCell")
}
