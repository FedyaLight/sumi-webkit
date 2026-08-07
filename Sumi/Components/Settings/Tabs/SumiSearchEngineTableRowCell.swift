import AppKit

final class SumiContextSelectingTableView: NSTableView {
    var contextMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return contextMenuProvider?()
    }
}

final class SumiSearchEngineSwitch: NSSwitch {
    var engineID = ""
}

final class SumiSearchEngineActionButton: NSButton {
    var engineID = ""
}

final class SumiSearchEngineRowCell: NSTableCellView {
    private let dragHandle = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let tabSearchSwitch = SumiSearchEngineSwitch()
    private let editButton = SumiSearchEngineActionButton()
    private let removeButton = SumiSearchEngineActionButton()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Reorder")
        dragHandle.contentTintColor = .tertiaryLabelColor
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        tabSearchSwitch.controlSize = .small
        tabSearchSwitch.translatesAutoresizingMaskIntoConstraints = false

        configureActionButton(
            editButton,
            symbolName: "pencil",
            accessibilityLabel: String(localized: "Edit Search Engine")
        )
        configureActionButton(
            removeButton,
            symbolName: "trash",
            accessibilityLabel: String(localized: "Remove Search Engine")
        )

        addSubview(dragHandle)
        addSubview(nameLabel)
        addSubview(editButton)
        addSubview(removeButton)
        addSubview(tabSearchSwitch)
        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dragHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 14),
            dragHandle.heightAnchor.constraint(equalToConstant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 9),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabSearchSwitch.leadingAnchor, constant: -10),
            tabSearchSwitch.centerXAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -SumiSearchEngineTableLayout.tabSearchControlCenterTrailingOffset
            ),
            tabSearchSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.leadingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -26),
            editButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 22),
            editButton.heightAnchor.constraint(equalToConstant: 22),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 22),
            removeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureActionButton(
        _ button: SumiSearchEngineActionButton,
        symbolName: String,
        accessibilityLabel: String
    ) {
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .inline
        button.controlSize = .small
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(
        engine: SumiSearchEngine,
        target: AnyObject,
        tabSearchAction: Selector,
        editAction: Selector,
        removeAction: Selector
    ) {
        nameLabel.stringValue = engine.name
        nameLabel.toolTip = engine.searchURLTemplate
        tabSearchSwitch.engineID = engine.id
        tabSearchSwitch.state = engine.tabSearchEnabled ? .on : .off
        tabSearchSwitch.target = target
        tabSearchSwitch.action = tabSearchAction
        tabSearchSwitch.toolTip = engine.tabSearchEnabled
            ? String(localized: "Disable Tab Search")
            : String(localized: "Enable Tab Search")
        editButton.engineID = engine.id
        editButton.target = target
        editButton.action = editAction
        removeButton.engineID = engine.id
        removeButton.target = target
        removeButton.action = removeAction
    }
}
