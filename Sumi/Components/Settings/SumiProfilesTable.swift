import AppKit
import SwiftUI

@MainActor
struct SumiProfilesTable: NSViewControllerRepresentable {
    let profiles: [Profile]
    let usage: [UUID: ProfileUsage]
    let retiringProfileIDs: Set<UUID>
    let onRename: (Profile, String) -> Bool
    let onAdd: () -> Void
    let onDelete: (Profile, NSWindow?) -> Void

    func makeNSViewController(context: Context) -> SumiProfilesTableViewController {
        SumiProfilesTableViewController(
            profiles: profiles,
            usage: usage,
            retiringProfileIDs: retiringProfileIDs,
            onRename: onRename,
            onAdd: onAdd,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: SumiProfilesTableViewController,
        context: Context
    ) {
        controller.update(
            profiles: profiles,
            usage: usage,
            retiringProfileIDs: retiringProfileIDs,
            onRename: onRename,
            onAdd: onAdd,
            onDelete: onDelete
        )
    }
}

@MainActor
final class SumiProfilesTableViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let profile = NSUserInterfaceItemIdentifier("profile")
        static let usage = NSUserInterfaceItemIdentifier("usage")
    }

    private struct RowSnapshot: Equatable {
        let id: UUID
        let name: String
        let usage: ProfileUsage
        let isRetiring: Bool
    }

    private let tableView = SumiProfilesNativeTableView()
    private let scrollView = NSScrollView()
    private let addRemoveControl = NSSegmentedControl()
    private let renameButton = NSButton(title: String(localized: "Rename"), target: nil, action: nil)

    private var profiles: [Profile]
    private var usage: [UUID: ProfileUsage]
    private var retiringProfileIDs: Set<UUID>
    private var onRename: (Profile, String) -> Bool
    private var onAdd: () -> Void
    private var onDelete: (Profile, NSWindow?) -> Void
    private var snapshot: [RowSnapshot]

    init(
        profiles: [Profile],
        usage: [UUID: ProfileUsage],
        retiringProfileIDs: Set<UUID>,
        onRename: @escaping (Profile, String) -> Bool,
        onAdd: @escaping () -> Void,
        onDelete: @escaping (Profile, NSWindow?) -> Void
    ) {
        self.profiles = profiles
        self.usage = usage
        self.retiringProfileIDs = retiringProfileIDs
        self.onRename = onRename
        self.onAdd = onAdd
        self.onDelete = onDelete
        self.snapshot = Self.makeSnapshot(
            profiles: profiles,
            usage: usage,
            retiringProfileIDs: retiringProfileIDs
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()

        let profileColumn = NSTableColumn(identifier: Column.profile)
        profileColumn.title = String(localized: "Profile")
        profileColumn.minWidth = 220
        profileColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(profileColumn)

        let usageColumn = NSTableColumn(identifier: Column.usage)
        usageColumn.title = String(localized: "Usage")
        usageColumn.width = 190
        usageColumn.minWidth = 140
        usageColumn.resizingMask = .userResizingMask
        tableView.addTableColumn(usageColumn)

        tableView.style = .fullWidth
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(renameSelectedProfile)
        tableView.onReturn = { [weak self] in self?.renameSelectedProfile() }
        tableView.onDelete = { [weak self] in self?.deleteSelectedProfile() }
        tableView.contextMenuProvider = { [weak self] in self?.makeContextMenu() }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        configureActionBar()
        let actionBarSpacer = NSView()
        actionBarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [addRemoveControl, actionBarSpacer, renameButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        updateActionAvailability()
    }

    func update(
        profiles: [Profile],
        usage: [UUID: ProfileUsage],
        retiringProfileIDs: Set<UUID>,
        onRename: @escaping (Profile, String) -> Bool,
        onAdd: @escaping () -> Void,
        onDelete: @escaping (Profile, NSWindow?) -> Void
    ) {
        self.onRename = onRename
        self.onAdd = onAdd
        self.onDelete = onDelete

        let selectedID = selectedProfile?.id
        let updatedSnapshot = Self.makeSnapshot(
            profiles: profiles,
            usage: usage,
            retiringProfileIDs: retiringProfileIDs
        )
        self.profiles = profiles
        self.usage = usage
        self.retiringProfileIDs = retiringProfileIDs
        guard updatedSnapshot != snapshot else {
            updateActionAvailability()
            return
        }

        snapshot = updatedSnapshot
        tableView.reloadData()
        if let selectedID,
           let selectedRow = profiles.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(
                IndexSet(integer: selectedRow),
                byExtendingSelection: false
            )
        }
        updateActionAvailability()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        profiles.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard profiles.indices.contains(row), let tableColumn else { return nil }
        let profile = profiles[row]
        let isRetiring = retiringProfileIDs.contains(profile.id)

        switch tableColumn.identifier {
        case Column.profile:
            let identifier = NSUserInterfaceItemIdentifier("ProfileNameCell")
            let cell = tableView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? SumiProfileNameCell ?? SumiProfileNameCell(identifier: identifier)
            cell.configure(
                profileID: profile.id,
                name: profile.name,
                isEditable: !isRetiring,
                onRename: { [weak self] profileID, name in
                    guard let self,
                          let profile = profiles.first(where: { $0.id == profileID })
                    else { return false }
                    return onRename(profile, name)
                }
            )
            return cell

        case Column.usage:
            let identifier = NSUserInterfaceItemIdentifier("ProfileUsageCell")
            let cell = tableView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? SumiProfileUsageCell ?? SumiProfileUsageCell(identifier: identifier)
            cell.configure(
                text: isRetiring
                    ? String(localized: "Deleting…")
                    : ProfileRetirementImpactPresentation.summary(
                        for: usage[profile.id] ?? .none
                    ),
                isRetiring: isRetiring
            )
            return cell

        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateActionAvailability()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SumiProfileTableRowView(showsSeparator: row < profiles.count - 1)
    }

    func tableView(
        _ tableView: NSTableView,
        shouldEdit tableColumn: NSTableColumn?,
        row: Int
    ) -> Bool {
        tableColumn?.identifier == Column.profile
            && profiles.indices.contains(row)
            && !retiringProfileIDs.contains(profiles[row].id)
    }

    @objc private func performAddRemoveAction(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            onAdd()
        case 1:
            deleteSelectedProfile()
        default:
            break
        }
    }

    @objc private func renameSelectedProfile() {
        let row = tableView.selectedRow
        guard profiles.indices.contains(row),
              !retiringProfileIDs.contains(profiles[row].id)
        else { return }
        guard let column = tableView.tableColumns.firstIndex(where: {
            $0.identifier == Column.profile
        }) else { return }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }

    @objc private func deleteSelectedProfile() {
        guard retiringProfileIDs.isEmpty, let selectedProfile else { return }
        onDelete(selectedProfile, view.window)
    }

    private var selectedProfile: Profile? {
        guard profiles.indices.contains(tableView.selectedRow) else { return nil }
        return profiles[tableView.selectedRow]
    }

    private func updateActionAvailability() {
        let canMutate = retiringProfileIDs.isEmpty
        let hasSelection = selectedProfile != nil
        addRemoveControl.setEnabled(canMutate, forSegment: 0)
        addRemoveControl.setEnabled(canMutate && hasSelection, forSegment: 1)
        renameButton.isEnabled = canMutate && hasSelection
    }

    private func makeContextMenu() -> NSMenu? {
        guard let selectedProfile else { return nil }
        let menu = NSMenu()
        let renameItem = NSMenuItem(
            title: String(localized: "Rename"),
            action: #selector(renameSelectedProfile),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.isEnabled = !retiringProfileIDs.contains(selectedProfile.id)
        menu.addItem(renameItem)
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(
            title: String(localized: "Delete Profile…"),
            action: #selector(deleteSelectedProfile),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = retiringProfileIDs.isEmpty
        menu.addItem(deleteItem)
        return menu
    }

    private func configureActionBar() {
        addRemoveControl.segmentCount = 2
        addRemoveControl.trackingMode = .momentary
        addRemoveControl.segmentStyle = .smallSquare
        addRemoveControl.controlSize = .small
        addRemoveControl.setImage(
            NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "Add Profile")),
            forSegment: 0
        )
        addRemoveControl.setImage(
            NSImage(systemSymbolName: "minus", accessibilityDescription: String(localized: "Delete Profile")),
            forSegment: 1
        )
        addRemoveControl.setToolTip(String(localized: "Add Profile"), forSegment: 0)
        addRemoveControl.setToolTip(String(localized: "Delete Profile"), forSegment: 1)
        addRemoveControl.setWidth(28, forSegment: 0)
        addRemoveControl.setWidth(28, forSegment: 1)
        addRemoveControl.target = self
        addRemoveControl.action = #selector(performAddRemoveAction(_:))

        renameButton.bezelStyle = .rounded
        renameButton.controlSize = .small
        renameButton.target = self
        renameButton.action = #selector(renameSelectedProfile)
    }

    private static func makeSnapshot(
        profiles: [Profile],
        usage: [UUID: ProfileUsage],
        retiringProfileIDs: Set<UUID>
    ) -> [RowSnapshot] {
        profiles.map { profile in
            RowSnapshot(
                id: profile.id,
                name: profile.name,
                usage: usage[profile.id] ?? .none,
                isRetiring: retiringProfileIDs.contains(profile.id)
            )
        }
    }
}

@MainActor
private final class SumiProfilesNativeTableView: NSTableView {
    var contextMenuProvider: (() -> NSMenu?)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        guard clickedRow >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        return contextMenuProvider?()
    }

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
}

@MainActor
private final class SumiProfileTableRowView: NSTableRowView {
    init(showsSeparator: Bool) {
        super.init(frame: .zero)

        guard showsSeparator else { return }
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class SumiProfileNameCell: NSTableCellView, NSTextFieldDelegate {
    private let profileIcon = NSImageView()
    private let nameField = NSTextField()
    private var profileID = UUID()
    private var committedName = ""
    private var onRename: ((UUID, String) -> Bool)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        profileIcon.image = NSImage(
            systemSymbolName: "person.crop.circle",
            accessibilityDescription: String(localized: "Profile")
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        )
        profileIcon.contentTintColor = .secondaryLabelColor
        profileIcon.imageScaling = .scaleProportionallyDown
        profileIcon.translatesAutoresizingMaskIntoConstraints = false

        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.font = .systemFont(ofSize: 13)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.focusRingType = .exterior
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(profileIcon)
        addSubview(nameField)
        NSLayoutConstraint.activate([
            profileIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            profileIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            profileIcon.widthAnchor.constraint(equalToConstant: 18),
            profileIcon.heightAnchor.constraint(equalToConstant: 18),
            nameField.leadingAnchor.constraint(equalTo: profileIcon.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView = profileIcon
        textField = nameField
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        profileID: UUID,
        name: String,
        isEditable: Bool,
        onRename: @escaping (UUID, String) -> Bool
    ) {
        self.profileID = profileID
        committedName = name
        nameField.stringValue = name
        nameField.isEditable = isEditable
        nameField.isSelectable = isEditable
        nameField.textColor = isEditable ? .labelColor : .tertiaryLabelColor
        self.onRename = onRename
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let proposedName = nameField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard proposedName != committedName else { return }
        guard onRename?(profileID, proposedName) == true else {
            nameField.stringValue = committedName
            NSSound.beep()
            return
        }
        committedName = proposedName
        nameField.stringValue = proposedName
    }
}

@MainActor
private final class SumiProfileUsageCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, isRetiring: Bool) {
        label.stringValue = text
        label.textColor = isRetiring ? .tertiaryLabelColor : .secondaryLabelColor
    }
}
