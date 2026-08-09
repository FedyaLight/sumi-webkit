import AppKit
import SumiWebRuntime

@MainActor
final class PagePresentationSurfaceView: NSView {
    let presentation: PagePresentation
    private let repairAction: ((Bool) -> Void)?

    init(
        presentation: PagePresentation,
        repairAction: ((Bool) -> Void)? = nil
    ) {
        self.presentation = presentation
        self.repairAction = repairAction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        guard case .recoveryFailure(
            _, let destination, let nativeSnapshotAvailable
        ) = presentation else {
            setAccessibilityElement(false)
            return
        }

        let title = NSTextField(labelWithString: "Page stopped working")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center
        title.maximumNumberOfLines = 2

        let detail = NSTextField(labelWithString: destination.absoluteString)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.lineBreakMode = .byTruncatingMiddle

        var arrangedViews: [NSView] = [title, detail]
        if repairAction != nil {
            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 8
            if nativeSnapshotAvailable {
                let restore = NSButton(
                    title: "Repair and Restore",
                    target: self,
                    action: #selector(repairAndRestore)
                )
                restore.bezelStyle = .rounded
                buttons.addArrangedSubview(restore)
            }
            let open = NSButton(
                title: "Open Address",
                target: self,
                action: #selector(openAddress)
            )
            open.bezelStyle = .rounded
            buttons.addArrangedSubview(open)
            arrangedViews.append(buttons)
        }

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.stringValue)
        setAccessibilityValue(detail.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        repairAction == nil ? nil : super.hitTest(point)
    }

    @objc private func repairAndRestore() { repairAction?(true) }

    @objc private func openAddress() { repairAction?(false) }

}

@MainActor
final class WindowWebContentPanePresenter {
    private let windowState: BrowserWindowState
    private let containerView: WindowWebContentSplitHostLayoutView
    private let compositorRuntime: WebViewCompositorRuntime
    private let hostRegistry: WindowWebContentHostRegistry
    private let hostResolver: WindowWebContentHostResolver
    private let hostAttachments: WindowWebContentHostAttachmentService
    private let browserContext: any WindowWebContentBrowserContext

    init(
        windowState: BrowserWindowState,
        containerView: WindowWebContentSplitHostLayoutView,
        compositorRuntime: WebViewCompositorRuntime,
        hostRegistry: WindowWebContentHostRegistry,
        hostResolver: WindowWebContentHostResolver,
        hostAttachments: WindowWebContentHostAttachmentService,
        browserContext: any WindowWebContentBrowserContext
    ) {
        self.windowState = windowState
        self.containerView = containerView
        self.compositorRuntime = compositorRuntime
        self.hostRegistry = hostRegistry
        self.hostResolver = hostResolver
        self.hostAttachments = hostAttachments
        self.browserContext = browserContext
    }

    @discardableResult
    func presentSinglePane(
        pane: WindowWebContentPaneDecision,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorRuntime.owns(containerRegistration) else { return false }
        containerView.setPaneLayout(.single)
        containerView.singlePaneView.isHidden = false

        if case .live = pane.presentation,
           let tab = pane.tab,
           let host = hostResolver.resolveHost(
               for: tab,
               slot: .single,
               containerRegistration: containerRegistration
           ) {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.attach(
                host,
                to: containerView.singlePaneView,
                containerRegistration: containerRegistration
            )
            guard compositorRuntime.owns(containerRegistration) else { return false }
            containerView.singlePaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: hostAttachments.shouldRemoveHostedSubview
            )
        } else {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.clearSinglePane()
            let presentation: PagePresentation
            if case .live(let pageID) = pane.presentation {
                presentation = .integrityFailure(pageID: pageID)
            } else {
                presentation = pane.presentation
            }
            containerView.singlePaneView.placePresentationSurface(
                surface(for: presentation)
            )
        }

        guard compositorRuntime.owns(containerRegistration) else { return false }
        hostAttachments.clearAllSplitPaneHosts()
        return compositorRuntime.owns(containerRegistration)
    }

    @discardableResult
    func presentSplitGroup(
        _ presentation: WindowSplitPresentation,
        panes: [WindowWebContentPaneDecision],
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorRuntime.owns(containerRegistration) else { return false }
        containerView.setPaneLayout(.split(presentation))

        let visibleTabIDs = Set(presentation.visibleTabIDs)
        for tabID in hostRegistry.splitPaneTabIds where !visibleTabIDs.contains(tabID) {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.clearSplitPaneHost(tabID)
        }

        for pane in panes {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            guard let pageID = pane.pageID else { continue }
            guard let paneView = containerView.paneView(for: pageID) else {
                hostAttachments.clearSplitPaneHost(pageID)
                continue
            }
            guard let memberID = presentation.memberID(for: pageID) else {
                preconditionFailure(
                    "Validated split presentation lost a runtime tab mapping"
                )
            }
            if case .live = pane.presentation,
               let tab = pane.tab,
               let host = hostResolver.resolveHost(
                for: tab,
                slot: .split(pageID),
                containerRegistration: containerRegistration
            ) {
                guard compositorRuntime.owns(containerRegistration) else { return false }
                containerView.configureSplitControls(
                    in: paneView,
                    tab: tab,
                    memberID: memberID,
                    groupID: presentation.groupID,
                    windowState: windowState
                )
                hostAttachments.attach(
                    host,
                    to: paneView,
                    containerRegistration: containerRegistration
                )
                guard compositorRuntime.owns(containerRegistration) else { return false }
                paneView.removeHostedSubviews(
                    keeping: host,
                    shouldRemove: hostAttachments.shouldRemoveHostedSubview
                )
            } else {
                guard compositorRuntime.owns(containerRegistration) else { return false }
                hostAttachments.clearSplitPaneHost(pageID)
                if let tab = pane.tab {
                    containerView.configureSplitControls(
                        in: paneView,
                        tab: tab,
                        memberID: memberID,
                        groupID: presentation.groupID,
                        windowState: windowState
                    )
                }
                let surfacePresentation: PagePresentation
                if case .live = pane.presentation {
                    surfacePresentation = .integrityFailure(pageID: pageID)
                } else {
                    surfacePresentation = pane.presentation
                }
                paneView.placePresentationSurface(
                    surface(for: surfacePresentation)
                )
            }
        }

        guard compositorRuntime.owns(containerRegistration) else { return false }
        hostAttachments.clearSinglePane()
        return compositorRuntime.owns(containerRegistration)
    }

    private func surface(
        for presentation: PagePresentation
    ) -> PagePresentationSurfaceView {
        guard case .recoveryFailure(let pageID, _, _) = presentation else {
            return PagePresentationSurfaceView(presentation: presentation)
        }
        return PagePresentationSurfaceView(
            presentation: presentation,
            repairAction: { [weak self] useNativeSnapshot in
                guard let self else { return }
                self.browserContext.repairFailedPage(
                    pageID,
                    in: self.windowState.id,
                    useNativeSnapshot: useNativeSnapshot
                )
            }
        )
    }
}
