//
//  General.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @State private var showingAddSite = false
    @State private var sitePendingRemoval: SiteSearchEntry?

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Window",
                subtitle: "Core browser-window behavior."
            ) {
                SettingsRow(
                    title: "Warn before quitting",
                    subtitle: "Ask for confirmation before closing Sumi."
                ) {
                    Toggle("", isOn: $settings.askBeforeQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Glance",
                    subtitle: "Preview links without fully opening a tab."
                ) {
                    Toggle("", isOn: $settings.glanceEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(
                title: "Search",
                subtitle: "Sumi routes searches through the canonical URL bar in the sidebar header."
            ) {
                SettingsRow(
                    title: "Default search engine",
                    subtitle: "Used for plain text typed into the URL bar."
                ) {
                    SearchEnginePopUpButton(
                        selection: $settings.searchEngineId,
                        customEngines: sumiSettings.customSearchEngines,
                        onAdd: addCustomSearchEngine,
                        onRemoveSelected: removeCustomSearchEngine
                    )
                    .settingsTrailingControl(width: 210)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Floating bar empty state",
                    subtitle: "Choose what appears before you start typing."
                ) {
                    Picker("", selection: $settings.floatingBarEmptyStateMode) {
                        ForEach(FloatingBarEmptyStateMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsTrailingControl(width: 160)
                }
            }

            SettingsSection(
                title: "Site Search",
                subtitle: "Type a site prefix in the floating bar, then press Tab to search that site."
            ) {
                if sumiSettings.siteSearchEntries.isEmpty {
                    SettingsEmptyState(
                        systemImage: "globe.badge.chevron.backward",
                        title: "No Site Searches",
                        detail: "Add a site search to jump directly into a website search field."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sumiSettings.siteSearchEntries) { entry in
                            siteSearchRow(entry)
                        }
                    }
                }

                SettingsDivider()

                HStack(spacing: 8) {
                    Spacer(minLength: 0)

                    Button {
                        showingAddSite = true
                    } label: {
                        Label("Add Site", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to Defaults") {
                        sumiSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                sumiSettings.siteSearchEntries.append(newEntry)
            }
        }
        .confirmationDialog(
            "Remove Site Search?",
            isPresented: siteRemovalBinding
        ) {
            Button("Remove", role: .destructive) {
                removePendingSiteSearch()
            }
            Button("Cancel", role: .cancel) {
                sitePendingRemoval = nil
            }
        } message: {
            Text(sitePendingRemoval?.name ?? "")
        }
    }

    private var siteRemovalBinding: Binding<Bool> {
        Binding(
            get: { sitePendingRemoval != nil },
            set: { isPresented in
                if !isPresented { sitePendingRemoval = nil }
            }
        )
    }

    private func siteSearchRow(_ entry: SiteSearchEntry) -> some View {
        SettingsRow(
            title: entry.name,
            systemImage: nil
        ) {
            HStack(spacing: 8) {
                Text(entry.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(entry.color)
                    .frame(width: 10, height: 10)

                Button(role: .destructive) {
                    sitePendingRemoval = entry
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help("Remove site search")
            }
        }
    }

    private func addCustomSearchEngine(_ newEngine: CustomSearchEngine) {
        sumiSettings.customSearchEngines.append(newEngine)
        sumiSettings.searchEngineId = newEngine.id.uuidString
    }

    private func removeCustomSearchEngine(id: UUID) {
        sumiSettings.customSearchEngines.removeAll { $0.id == id }
        if sumiSettings.searchEngineId == id.uuidString {
            sumiSettings.searchEngineId = SearchProvider.google.rawValue
        }
    }

    private func removePendingSiteSearch() {
        guard let entry = sitePendingRemoval else { return }
        sumiSettings.siteSearchEntries.removeAll { $0.id == entry.id }
        sitePendingRemoval = nil
    }
}

@MainActor
private struct SearchEnginePopUpButton: NSViewRepresentable {
    @Binding var selection: String
    let customEngines: [CustomSearchEngine]
    let onAdd: (CustomSearchEngine) -> Void
    let onRemoveSelected: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.rebuild(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuild(button)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SearchEnginePopUpButton
        weak var button: NSPopUpButton?

        init(_ parent: SearchEnginePopUpButton) {
            self.parent = parent
        }

        func rebuild(_ button: NSPopUpButton) {
            self.button = button
            button.removeAllItems()

            for provider in SearchProvider.allCases {
                addItem(
                    to: button,
                    title: provider.displayName,
                    representedObject: provider.rawValue,
                    state: parent.selection == provider.rawValue ? .on : .off,
                    action: #selector(selectSearchEngine(_:))
                )
            }

            if !parent.customEngines.isEmpty {
                button.menu?.addItem(.separator())

                for engine in parent.customEngines {
                    addItem(
                        to: button,
                        title: engine.name,
                        representedObject: engine.id.uuidString,
                        state: parent.selection == engine.id.uuidString ? .on : .off,
                        action: #selector(selectSearchEngine(_:))
                    )
                }
            }

            button.menu?.addItem(.separator())

            addItem(
                to: button,
                title: "Add Search Engine...",
                representedObject: nil,
                state: .off,
                action: #selector(addSearchEngine(_:))
            )

            let selectedCustomEngine = selectedCustomEngine
            let removeTitle = selectedCustomEngine.map { "Remove \"\($0.name)\"..." } ?? "Remove Custom Search Engine"
            let removeItem = addItem(
                to: button,
                title: removeTitle,
                representedObject: selectedCustomEngine?.id.uuidString,
                state: .off,
                action: #selector(removeSelectedSearchEngine(_:))
            )
            removeItem.isEnabled = selectedCustomEngine != nil

            if let selectedItem = button.itemArray.first(where: { ($0.representedObject as? String) == parent.selection }) {
                button.select(selectedItem)
            }
        }

        @discardableResult
        private func addItem(
            to button: NSPopUpButton,
            title: String,
            representedObject: String?,
            state: NSControl.StateValue,
            action: Selector
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = representedObject
            item.state = state
            button.menu?.addItem(item)
            return item
        }

        private var selectedCustomEngine: CustomSearchEngine? {
            parent.customEngines.first { $0.id.uuidString == parent.selection }
        }

        @objc private func selectSearchEngine(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            parent.selection = id
        }

        @objc private func addSearchEngine(_ sender: NSMenuItem) {
            resetVisibleSelection()
            NativeCustomSearchEngineAlert.present(from: button?.window ?? NSApp.keyWindow) { [weak self] engine in
                self?.parent.onAdd(engine)
            }
        }

        @objc private func removeSelectedSearchEngine(_ sender: NSMenuItem) {
            resetVisibleSelection()
            guard
                let idString = sender.representedObject as? String,
                let id = UUID(uuidString: idString),
                let engine = parent.customEngines.first(where: { $0.id == id })
            else {
                return
            }

            let alert = NSAlert()
            alert.messageText = "Remove Search Engine?"
            alert.informativeText = "\"\(engine.name)\" will be removed from the default search engine menu."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")

            let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.parent.onRemoveSelected(id)
            }

            if let window = button?.window ?? NSApp.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(alert.runModal())
            }
        }

        private func resetVisibleSelection() {
            guard
                let button,
                let selectedItem = button.itemArray.first(where: { ($0.representedObject as? String) == parent.selection })
            else {
                return
            }
            button.select(selectedItem)
        }
    }
}

@MainActor
private enum NativeCustomSearchEngineAlert {
    static func present(from window: NSWindow?, completion: @escaping (CustomSearchEngine) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Add Search Engine"
        alert.alertStyle = .informational

        let nameField = VerticallyCenteredTextField(string: "")
        nameField.placeholderString = "Startpage"
        nameField.controlSize = .regular
        nameField.font = .preferredFont(forTextStyle: .body)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let templateField = VerticallyCenteredTextField(string: "")
        templateField.placeholderString = "https://www.example.com/search?q=%@"
        templateField.controlSize = .regular
        templateField.font = .preferredFont(forTextStyle: .body)
        templateField.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "Enter a name and a search URL that uses %@ where the query should appear."
        )
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = NSTextField(labelWithString: "")
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.alignment = .right
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let templateLabel = NSTextField(labelWithString: "URL:")
        templateLabel.alignment = .right
        templateLabel.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [nameLabel, nameField],
            [templateLabel, templateField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 0).width = 64
        grid.column(at: 1).width = 340
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let accessoryView = NSStackView(views: [descriptionLabel, grid, messageLabel])
        accessoryView.orientation = .vertical
        accessoryView.alignment = .leading
        accessoryView.spacing = 12
        accessoryView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            descriptionLabel.widthAnchor.constraint(equalToConstant: 420),
            grid.widthAnchor.constraint(equalToConstant: 420),
            messageLabel.widthAnchor.constraint(equalToConstant: 420),
            nameField.heightAnchor.constraint(equalToConstant: 30),
            templateField.heightAnchor.constraint(equalToConstant: 30),
            nameField.heightAnchor.constraint(equalTo: templateField.heightAnchor)
        ])
        accessoryView.layoutSubtreeIfNeeded()
        accessoryView.setFrameSize(NSSize(width: 420, height: accessoryView.fittingSize.height))

        alert.accessoryView = accessoryView
        alert.window.initialFirstResponder = nameField

        let addButton = alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        addButton.isEnabled = false

        func validationMessage() -> String? {
            validateCustomSearchEngine(
                name: nameField.stringValue,
                urlTemplate: templateField.stringValue
            )
        }

        func updateValidationState() {
            let message = validationMessage()
            addButton.isEnabled = message == nil
            messageLabel.stringValue = message ?? "Example: https://www.example.com/search?q=%@"
            messageLabel.textColor = message == nil ? .secondaryLabelColor : .systemRed
        }

        let fieldDelegate = SearchEngineAlertFieldDelegate {
            updateValidationState()
        }
        nameField.delegate = fieldDelegate
        templateField.delegate = fieldDelegate
        updateValidationState()

        let responseHandler: (NSApplication.ModalResponse) -> Void = { response in
            _ = fieldDelegate

            guard response == .alertFirstButtonReturn, validationMessage() == nil else { return }
            completion(
                CustomSearchEngine(
                    name: trimmed(nameField.stringValue),
                    urlTemplate: trimmed(templateField.stringValue)
                )
            )
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: responseHandler)
        } else {
            responseHandler(alert.runModal())
        }
    }

    private static func validateCustomSearchEngine(name: String, urlTemplate: String) -> String? {
        let trimmedName = trimmed(name)
        let trimmedURLTemplate = trimmed(urlTemplate)
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard trimmedURLTemplate.contains("%@") else {
            return "URL template must contain %@ where the query should go."
        }
        let sample = trimmedURLTemplate.replacingOccurrences(of: "%@", with: "sumi")
        guard let url = URL(string: sample),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            return "Enter a valid http or https URL template."
        }
        return nil
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class SearchEngineAlertFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange()
    }
}

private final class VerticallyCenteredTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCell()
    }

    private func configureCell() {
        let centeredCell = VerticallyCenteredTextFieldCell(textCell: stringValue)
        centeredCell.isEditable = isEditable
        centeredCell.isSelectable = isSelectable
        centeredCell.isBordered = isBordered
        centeredCell.isBezeled = isBezeled
        centeredCell.bezelStyle = .roundedBezel
        centeredCell.usesSingleLineMode = true
        centeredCell.lineBreakMode = .byTruncatingTail
        cell = centeredCell
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(forBounds: super.drawingRect(forBounds: rect))
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(forBounds: super.titleRect(forBounds: rect))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    private func centeredRect(forBounds rect: NSRect) -> NSRect {
        guard let font else { return rect }
        let textHeight = ceil(font.ascender - font.descender)
        let offset = max(0, floor((rect.height - textHeight) / 2) - 1)
        return rect.insetBy(dx: 0, dy: offset)
    }
}
