import AppKit

@MainActor
final class SumiHistoryFaviconCellView: NSTableCellView {
    private let faviconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?
    private var representedItemID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        faviconView.imageScaling = .scaleProportionallyDown
        faviconView.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [faviconView, titleLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            faviconView.widthAnchor.constraint(equalToConstant: 14),
            faviconView.heightAnchor.constraint(equalToConstant: 14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        loadTask?.cancel()
    }

    func configure(
        item: HistoryListItem,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    ) {
        representedItemID = item.id
        titleLabel.stringValue = item.displayTitle
        toolTip = item.displayTitle
        loadTask?.cancel()

        let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        let cached = TabFaviconStore.getCachedImage(
            forDocumentURL: item.url,
            partition: partition,
            context: .historyBookmarkRow,
            imageReader: imageReader
        )
        faviconView.image = cached ?? fallback
        loadTask = Task { @MainActor [weak self] in
            let image = await TabFaviconStore.loadCachedDisplayImage(
                forDocumentURL: item.url,
                partition: partition,
                context: .historyBookmarkRow,
                priority: .historyBookmarkVisibleRow,
                imageReader: imageReader
            )
            guard !Task.isCancelled, self?.representedItemID == item.id else { return }
            self?.faviconView.image = image ?? cached ?? fallback
        }
    }
}

@MainActor
final class SumiHistorySectionCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.image = NSImage(
            systemSymbolName: "clock",
            accessibilityDescription: String(localized: "History")
        )
        iconView.contentTintColor = .secondaryLabelColor
        iconView.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [iconView, titleLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.stringValue = title
        toolTip = title
    }
}
