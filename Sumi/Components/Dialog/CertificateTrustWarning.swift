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
        hostLabel = NSTextField(labelWithString: session.host)
        detailLabel = NSTextField(
            labelWithString: String(
                localized: "The certificate presented by this website could not be verified by macOS. Someone may be trying to impersonate this site and intercept your information."
            )
        )
        closeButton = NSButton(
            title: String(localized: "Close Page"),
            target: nil,
            action: nil
        )
        visitButton = NSButton(
            title: String(localized: "Visit Anyway"),
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
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "lock.slash.fill",
            accessibilityDescription: String(localized: "This Connection Is Not Secure")
        )
        iconView.contentTintColor = .systemRed
        iconView.imageScaling = .scaleProportionallyUpOrDown

        configure(label: titleLabel, font: .systemFont(ofSize: 28, weight: .bold))
        configure(label: hostLabel, font: .systemFont(ofSize: 15, weight: .semibold))
        configure(label: detailLabel, font: .systemFont(ofSize: 15))
        detailLabel.textColor = .secondaryLabelColor

        closeButton.target = self
        closeButton.action = #selector(closePage)
        closeButton.bezelStyle = .rounded
        closeButton.bezelColor = .controlAccentColor
        closeButton.keyEquivalent = "\r"

        visitButton.target = self
        visitButton.action = #selector(visitSite)
        visitButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [closeButton, visitButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let content = NSStackView(views: [iconView, titleLabel, hostLabel, detailLabel, buttons])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.setCustomSpacing(20, after: iconView)
        content.setCustomSpacing(20, after: detailLabel)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            detailLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])

        setAccessibilityLabel(String(localized: "This Connection Is Not Secure"))
    }

    private func configure(label: NSTextField, font: NSFont) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.alignment = .center
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
