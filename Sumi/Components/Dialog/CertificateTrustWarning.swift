import AppKit

@MainActor
final class CertificateTrustWarningSession {
    let host: String

    private let onVisitSite: () -> Void
    private let onClosePage: () -> Void
    private let onCancel: () -> Void
    private var didComplete = false

    init(
        host: String,
        onVisitSite: @escaping () -> Void,
        onClosePage: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.host = host
        self.onVisitSite = onVisitSite
        self.onClosePage = onClosePage
        self.onCancel = onCancel
    }

    func visitSite() {
        guard didComplete == false else { return }
        didComplete = true
        onVisitSite()
    }

    func closePage() {
        guard didComplete == false else { return }
        didComplete = true
        onClosePage()
    }

    func cancel() {
        guard didComplete == false else { return }
        didComplete = true
        onCancel()
    }
}

@MainActor
final class CertificateTrustWarningView: NSView {
    let session: CertificateTrustWarningSession
    private let onFinish: (CertificateTrustWarningView) -> Void
    private let panel = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let hostLabel: NSTextField
    private let detailLabel: NSTextField
    private let closeButton: NSButton
    private let visitButton: NSButton

    init(
        session: CertificateTrustWarningSession,
        onFinish: @escaping (CertificateTrustWarningView) -> Void
    ) {
        self.session = session
        self.onFinish = onFinish
        titleLabel = NSTextField(labelWithString: String(localized: "This Connection Is Not Secure"))
        hostLabel = NSTextField(
            labelWithString: String(
                localized: "This site may be impersonating \(session.host) to steal your personal or financial information."
            )
        )
        detailLabel = NSTextField(
            labelWithString: String(
                localized: "The certificate presented by this website could not be verified by macOS. If you continue, you accept the risk for this visit."
            )
        )
        closeButton = NSButton(
            title: String(localized: "Close Page"),
            target: nil,
            action: nil
        )
        visitButton = NSButton(
            title: String(localized: "Visit Site"),
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        addSubview(panel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "lock.slash.fill",
            accessibilityDescription: String(localized: "This Connection Is Not Secure")
        )
        iconView.contentTintColor = .systemRed
        iconView.imageScaling = .scaleProportionallyUpOrDown

        configure(label: titleLabel, font: .systemFont(ofSize: 22, weight: .semibold))
        configure(label: hostLabel, font: .systemFont(ofSize: 15))
        configure(label: detailLabel, font: .systemFont(ofSize: 15))
        hostLabel.textColor = .secondaryLabelColor

        closeButton.target = self
        closeButton.action = #selector(closePage)
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"

        visitButton.target = self
        visitButton.action = #selector(visitSite)
        visitButton.bezelStyle = .rounded
        visitButton.bezelColor = .controlAccentColor
        visitButton.keyEquivalent = "\r"

        let textStack = NSStackView(views: [titleLabel, hostLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 5
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView(views: [iconView, textStack])
        titleRow.orientation = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = 14
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        let buttons = NSStackView(views: [spacer, closeButton, visitButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [titleRow, detailLabel, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)

        let preferredPanelWidth = panel.widthAnchor.constraint(equalToConstant: 520)
        preferredPanelWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            preferredPanelWidth,
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 28),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -28),

            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            titleRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1),
        ])

        setAccessibilityLabel(String(localized: "This Connection Is Not Secure"))
    }

    private func configure(label: NSTextField, font: NSFont) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @objc private func closePage() {
        onFinish(self)
        removeFromSuperview()
        session.closePage()
    }

    @objc private func visitSite() {
        onFinish(self)
        removeFromSuperview()
        session.visitSite()
    }
}
