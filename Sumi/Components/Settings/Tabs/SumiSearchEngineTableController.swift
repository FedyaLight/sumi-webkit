import AppKit
import SwiftUI

struct SumiSearchEngineTable: NSViewControllerRepresentable {
    @Binding var searchEngines: [SumiSearchEngine]
    @Binding var filterText: String

    func makeNSViewController(context: Context) -> SumiSearchEngineTableViewController {
        SumiSearchEngineTableViewController(
            searchEngines: searchEngines,
            filterText: filterText,
            onChange: { searchEngines = $0 }
        )
    }

    func updateNSViewController(
        _ controller: SumiSearchEngineTableViewController,
        context: Context
    ) {
        controller.replaceSearchEngines(searchEngines)
        controller.replaceFilterText(filterText)
    }
}

@MainActor
final class SumiSearchEngineTableViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let dragType = NSPasteboard.PasteboardType("dev.sumi.search-engine-row")

    private let addButton = NSButton()
    private let restoreButton = NSButton()
    private let tableView = SumiContextSelectingTableView()
    private let tableContainer = NSView()
    private let onChange: ([SumiSearchEngine]) -> Void
    private var tableHeightConstraint: NSLayoutConstraint?

    private var searchEngines: [SumiSearchEngine]
    private var filterText: String
    private var displayedEngines: [SumiSearchEngine] = []

    init(
        searchEngines: [SumiSearchEngine],
        filterText: String,
        onChange: @escaping ([SumiSearchEngine]) -> Void
    ) {
        self.searchEngines = searchEngines
        self.filterText = filterText
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        configureTable()
        configureFooterButtons()

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [addButton, footerSpacer, restoreButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        restoreButton.setContentHuggingPriority(.required, for: .horizontal)

        view.addSubview(tableContainer)
        view.addSubview(footer)
        let tableHeightConstraint = tableContainer.heightAnchor.constraint(
            equalToConstant: SumiSearchEngineTableLayout.tableHeight(
                engineCount: searchEngines.count
            )
        )
        self.tableHeightConstraint = tableHeightConstraint
        NSLayoutConstraint.activate([
            tableContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableContainer.topAnchor.constraint(equalTo: view.topAnchor),
            tableHeightConstraint,
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.topAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: 10),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reload()
    }

    func replaceSearchEngines(_ engines: [SumiSearchEngine]) {
        guard engines != searchEngines else { return }
        searchEngines = engines
        reload(preservingSelection: true)
    }

    func replaceFilterText(_ text: String) {
        guard text != filterText else { return }
        filterText = text
        reload(preservingSelection: true)
    }

    private func configureFooterButtons() {
        addButton.title = String(localized: "Add")
        addButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: String(localized: "Add")
        )
        addButton.imagePosition = .imageLeading
        addButton.toolTip = String(localized: "Add Search Engine")
        addButton.bezelStyle = .rounded
        addButton.bezelColor = .controlAccentColor
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addSearchEngine)

        restoreButton.title = String(localized: "Restore Defaults…")
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaults)
    }

    private func configureTable() {
        let headerView = makeTableHeader()
        let engineColumn = NSTableColumn(identifier: .init("engine"))
        engineColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(engineColumn)
        tableView.headerView = nil
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = SumiSearchEngineTableLayout.rowHeight
        tableView.intercellSpacing = NSSize(
            width: 0,
            height: SumiSearchEngineTableLayout.intercellSpacing
        )
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editSelectedSearchEngine)
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.contextMenuProvider = { [weak self] in self?.makeContextMenu() }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.wantsLayer = true
        tableContainer.layer?.cornerRadius = 8
        tableContainer.layer?.borderWidth = 1
        tableContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        tableContainer.layer?.masksToBounds = true
        tableContainer.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.addSubview(headerView)
        tableContainer.addSubview(tableView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor, constant: 1),
            headerView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor, constant: -1),
            headerView.topAnchor.constraint(equalTo: tableContainer.topAnchor, constant: 1),
            headerView.heightAnchor.constraint(equalToConstant: SumiSearchEngineTableLayout.headerHeight),
            tableView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor, constant: 1),
            tableView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor, constant: -1),
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: -1),
        ])
    }

    private func makeTableHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let engineLabel = NSTextField(labelWithString: String(localized: "Search Engine"))
        let tabSearchLabel = NSTextField(labelWithString: String(localized: "Tab Search"))
        for label in [engineLabel, tabSearchLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(label)
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(separator)

        NSLayoutConstraint.activate([
            engineLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 33),
            engineLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            tabSearchLabel.centerXAnchor.constraint(
                equalTo: header.trailingAnchor,
                constant: -SumiSearchEngineTableLayout.tabSearchHeaderCenterTrailingOffset
            ),
            tabSearchLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        return header
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedEngines.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard displayedEngines.indices.contains(row), tableColumn != nil else { return nil }
        let engine = displayedEngines[row]
        return engineCell(for: engine)
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> NSPasteboardWriting? {
        guard !isFiltering, displayedEngines.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(displayedEngines[row].id, forType: Self.dragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard !isFiltering, dropOperation == .above else { return [] }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard !isFiltering,
              let engineID = info.draggingPasteboard.string(forType: Self.dragType),
              searchEngines.contains(where: { $0.id == engineID })
        else { return false }

        updateEngines(
            GeneralSearchEngineMutation.moving(
                ReorderMove(id: engineID, targetIndex: row),
                in: searchEngines
            ),
            selecting: engineID
        )
        return true
    }

    @objc private func addSearchEngine() {
        presentEditor(engine: nil)
    }

    @objc private func editSelectedSearchEngine() {
        guard let engine = selectedEngine else { return }
        presentEditor(engine: engine)
    }

    @objc private func editSearchEngine(_ sender: SumiSearchEngineActionButton) {
        guard let engine = searchEngine(withID: sender.engineID) else { return }
        select(engineID: engine.id)
        presentEditor(engine: engine)
    }

    @objc private func removeSelectedSearchEngine() {
        guard let engine = selectedEngine else { return }
        remove(engine: engine)
    }

    @objc private func removeSearchEngine(_ sender: SumiSearchEngineActionButton) {
        guard let engine = searchEngine(withID: sender.engineID) else { return }
        select(engineID: engine.id)
        remove(engine: engine)
    }

    private func remove(engine: SumiSearchEngine) {
        guard searchEngines.count > 1,
              let window = view.window
        else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "Remove \(engine.name)?")
        alert.informativeText = String(
            localized: "This search engine will no longer be available in the URL bar or Tab Search."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Remove"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  let updated = GeneralSearchEngineMutation.removing(
                    engineID: engine.id,
                    from: searchEngines
                  )
            else { return }
            updateEngines(updated)
        }
    }

    @objc private func toggleSelectedTabSearch() {
        guard let engine = selectedEngine else { return }
        updateEngines(
            GeneralSearchEngineMutation.settingTabSearch(
                !engine.tabSearchEnabled,
                for: engine.id,
                in: searchEngines
            ),
            selecting: engine.id
        )
    }

    @objc private func restoreDefaults() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Restore Default Search Engines?")
        alert.informativeText = String(
            localized: "Your current list and priority order will be replaced with Sumi's defaults."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Restore Defaults"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.updateEngines(SumiSearchEngine.defaultEngines())
        }
    }

    @objc private func tabSearchSwitchChanged(_ sender: SumiSearchEngineSwitch) {
        updateEngines(
            GeneralSearchEngineMutation.settingTabSearch(
                sender.state == .on,
                for: sender.engineID,
                in: searchEngines
            ),
            selecting: sender.engineID
        )
    }

    private var selectedEngine: SumiSearchEngine? {
        guard displayedEngines.indices.contains(tableView.selectedRow) else { return nil }
        return displayedEngines[tableView.selectedRow]
    }

    private var isFiltering: Bool {
        !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload(preservingSelection: Bool = false) {
        let selectedID = preservingSelection ? selectedEngine?.id : nil
        displayedEngines = searchEngines.filter { $0.matchesFilter(filterText) }
        tableHeightConstraint?.constant = SumiSearchEngineTableLayout.tableHeight(
            engineCount: searchEngines.count
        )
        tableView.reloadData()
        if let selectedID {
            select(engineID: selectedID)
        }
    }

    private func updateEngines(_ engines: [SumiSearchEngine], selecting engineID: String? = nil) {
        guard engines != searchEngines else { return }
        searchEngines = engines
        onChange(engines)
        reload()
        if let engineID {
            select(engineID: engineID)
        }
    }

    private func select(engineID: String) {
        guard let row = displayedEngines.firstIndex(where: { $0.id == engineID }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func searchEngine(withID id: String) -> SumiSearchEngine? {
        searchEngines.first { $0.id == id }
    }

    private func engineCell(for engine: SumiSearchEngine) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("SearchEngineRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SumiSearchEngineRowCell
            ?? SumiSearchEngineRowCell(identifier: identifier)
        cell.configure(
            engine: engine,
            target: self,
            tabSearchAction: #selector(tabSearchSwitchChanged(_:)),
            editAction: #selector(editSearchEngine(_:)),
            removeAction: #selector(removeSearchEngine(_:))
        )
        return cell
    }

    private func makeContextMenu() -> NSMenu? {
        guard let engine = selectedEngine else { return nil }
        let menu = NSMenu()
        menu.delegate = self
        let edit = NSMenuItem(
            title: String(localized: "Edit…"),
            action: #selector(editSelectedSearchEngine),
            keyEquivalent: ""
        )
        edit.target = self
        menu.addItem(edit)
        let toggleTitle = engine.tabSearchEnabled
            ? String(localized: "Disable Tab Search")
            : String(localized: "Enable Tab Search")
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleSelectedTabSearch), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let remove = NSMenuItem(
            title: String(localized: "Remove"),
            action: #selector(removeSelectedSearchEngine),
            keyEquivalent: ""
        )
        remove.target = self
        remove.isEnabled = searchEngines.count > 1
        menu.addItem(remove)
        return menu
    }

    private func presentEditor(engine: SumiSearchEngine?) {
        guard let window = view.window else { return }
        let editor = SumiSearchEngineEditorAlert(engine: engine)
        editor.beginSheetModal(for: window) { [weak self] savedEngine in
            guard let self, let savedEngine else { return }
            updateEngines(
                GeneralSearchEngineMutation.upserting(savedEngine, in: searchEngines),
                selecting: savedEngine.id
            )
        }
    }
}
