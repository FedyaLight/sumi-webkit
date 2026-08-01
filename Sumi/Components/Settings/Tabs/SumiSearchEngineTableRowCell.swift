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

final class SumiSearchEngineRowCell: NSTableCellView {
    private let dragHandle = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let tabSearchLabel = NSTextField(labelWithString: String(localized: "Tab Search"))
    private let tabSearchSwitch = SumiSearchEngineSwitch()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        dragHandle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Reorder")
        dragHandle.contentTintColor = .tertiaryLabelColor
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        tabSearchLabel.font = .systemFont(ofSize: 11)
        tabSearchLabel.textColor = .secondaryLabelColor
        tabSearchLabel.setContentHuggingPriority(.required, for: .horizontal)
        tabSearchLabel.translatesAutoresizingMaskIntoConstraints = false
        tabSearchSwitch.controlSize = .small
        tabSearchSwitch.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dragHandle)
        addSubview(nameLabel)
        addSubview(tabSearchLabel)
        addSubview(tabSearchSwitch)
        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dragHandle.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 14),
            dragHandle.heightAnchor.constraint(equalToConstant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: dragHandle.trailingAnchor, constant: 9),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabSearchLabel.leadingAnchor, constant: -14),
            tabSearchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabSearchSwitch.leadingAnchor.constraint(equalTo: tabSearchLabel.trailingAnchor, constant: 8),
            tabSearchSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            tabSearchSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        engine: SumiSearchEngine,
        target: AnyObject,
        action: Selector
    ) {
        nameLabel.stringValue = engine.name
        nameLabel.toolTip = engine.searchURLTemplate
        tabSearchSwitch.engineID = engine.id
        tabSearchSwitch.state = engine.tabSearchEnabled ? .on : .off
        tabSearchSwitch.target = target
        tabSearchSwitch.action = action
        tabSearchSwitch.toolTip = engine.tabSearchEnabled
            ? String(localized: "Disable Tab Search")
            : String(localized: "Enable Tab Search")
    }
}
