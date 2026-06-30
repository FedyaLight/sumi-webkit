import AppKit
import QuartzCore

@MainActor
final class SplitPaneControlsView: NSVisualEffectView {
    private let stackView = NSStackView()
    private let dragButton = SplitPaneDragButton()
    private let expandButton = SplitPaneToolbarButton(icon: .fullscreen)
    private weak var splitManager: SplitViewManager?
    private weak var windowState: BrowserWindowState?
    private weak var tab: Tab?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 13
        stackView.edgeInsets = NSEdgeInsets(top: 6.5, left: 9.5, bottom: 3.5, right: 9.5)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        dragButton.toolTip = "Rearrange Split"
        expandButton.toolTip = "Expand Tab"
        expandButton.target = self
        expandButton.action = #selector(expandTab)
        stackView.addArrangedSubview(dragButton)
        stackView.addArrangedSubview(expandButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 26)
    }

    func configure(
        tab: Tab,
        splitManager: SplitViewManager,
        windowState: BrowserWindowState,
        sidebarDragState: SidebarDragState
    ) {
        self.tab = tab
        self.splitManager = splitManager
        self.windowState = windowState
        dragButton.configure(
            tab: tab,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
    }

    func setSplitDropShieldHandler(_ handler: @escaping (Bool) -> Void) {
        dragButton.setSplitDropShieldHandler(handler)
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0
        guard abs(alphaValue - targetAlpha) > 0.001 else { return }

        let updates = { self.alphaValue = targetAlpha }
        guard animated else {
            updates()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = targetAlpha
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue > 0.05 ? super.hitTest(point) : nil
    }

    @objc private func expandTab() {
        guard let tab, let splitManager, let windowState else { return }
        splitManager.expandSplitPane(tabId: tab.id, in: windowState)
    }
}

private enum SplitPaneToolbarIcon {
    case dragHandle
    case fullscreen

    var image: NSImage {
        switch self {
        case .dragHandle:
            return Self.dragHandleImage
        case .fullscreen:
            return Self.fullscreenImage
        }
    }

    private static let dragHandleImage: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        NSColor.black.setFill()
        let dotDiameter: CGFloat = 1.2
        let dotOrigins: [CGPoint] = [
            CGPoint(x: 2.6, y: 4.0),
            CGPoint(x: 6.4, y: 4.0),
            CGPoint(x: 10.2, y: 4.0),
            CGPoint(x: 2.6, y: 8.8),
            CGPoint(x: 6.4, y: 8.8),
            CGPoint(x: 10.2, y: 8.8),
        ]
        for origin in dotOrigins {
            NSBezierPath(ovalIn: NSRect(
                x: origin.x,
                y: origin.y,
                width: dotDiameter,
                height: dotDiameter
            )).fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()

    private static let fullscreenImage: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: CGPoint(x: 8.4, y: 11.9))
        path.line(to: CGPoint(x: 11.9, y: 11.9))
        path.line(to: CGPoint(x: 11.9, y: 8.4))
        path.move(to: CGPoint(x: 11.9, y: 11.9))
        path.line(to: CGPoint(x: 8.4, y: 8.4))

        path.move(to: CGPoint(x: 2.1, y: 5.6))
        path.line(to: CGPoint(x: 2.1, y: 2.1))
        path.line(to: CGPoint(x: 5.6, y: 2.1))
        path.move(to: CGPoint(x: 2.1, y: 2.1))
        path.line(to: CGPoint(x: 5.6, y: 5.6))

        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

private class SplitPaneToolbarButton: NSButton {
    init(icon: SplitPaneToolbarIcon) {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        image = icon.image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }
}

private final class SplitPaneDragButton: SplitPaneToolbarButton, NSDraggingSource {
    private static let transparentDragImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
    }()

    private weak var tab: Tab?
    private weak var windowState: BrowserWindowState?
    private var sidebarDragState: SidebarDragState?
    private var didStartDrag = false
    private var mouseDownEvent: NSEvent?
    private var splitDropShieldHandler: ((Bool) -> Void)?

    init() {
        super.init(icon: .dragHandle)
        contentTintColor = .labelColor
    }

    func configure(
        tab: Tab,
        windowState: BrowserWindowState,
        sidebarDragState: SidebarDragState
    ) {
        self.tab = tab
        self.windowState = windowState
        self.sidebarDragState = sidebarDragState
    }

    func setSplitDropShieldHandler(_ handler: @escaping (Bool) -> Void) {
        splitDropShieldHandler = handler
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag else { return }
        startDrag(with: mouseDownEvent ?? event, sessionEvent: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if !didStartDrag {
            super.mouseUp(with: event)
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard let locations = SidebarDragLocationMapper.sourceLocationsFromScreenPoint(
            callbackScreenPoint: screenPoint,
            in: self
        ) else { return }
        sidebarDragState?.updateDragLocation(
            locations.dropLocation,
            previewLocation: locations.previewLocation
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        sidebarDragState?.resetInteractionState()
        setSplitDropShieldActive(false)
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        didStartDrag = false
        mouseDownEvent = nil
    }

    private func startDrag(with event: NSEvent, sessionEvent: NSEvent) {
        guard let tab, let windowState, let sidebarDragState else { return }
        let spaceId = tab.spaceId ?? windowState.currentSpaceId
        guard let spaceId else { return }

        let item = SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
        let scope = SidebarDragScope(
            windowId: windowState.id,
            spaceId: spaceId,
            profileId: windowState.currentProfileId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: tab.id,
            sourceItemKind: .tab
        )

        let localPoint = convert(event.locationInWindow, from: nil)
        let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromLocalPoint: localPoint,
            in: self
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromLocalPoint: localPoint,
            in: self
        )
        let previewModel = SidebarDragPreviewModel(
            item: item,
            sourceZone: .spaceRegular(spaceId),
            baseKind: .row,
            previewIcon: tab.favicon,
            chromeTemplateSystemImageName: nil,
            sourceSize: CGSize(width: 180, height: SidebarRowLayout.rowHeight),
            normalizedTopLeadingAnchor: CGPoint(x: 0.5, y: 0.5),
            pinnedConfig: .large,
            shortcutPresentationState: nil,
            folderGlyphPresentation: nil,
            folderGlyphPalette: nil
        )

        didStartDrag = true
        sidebarDragState.beginInternalDragSession(
            itemId: tab.id,
            location: dragLocation,
            previewLocation: previewLocation,
            previewKind: .row,
            previewAssets: [:],
            previewModel: previewModel,
            scope: scope
        )
        setSplitDropShieldActive(true)

        let dragItem = NSDraggingItem(pasteboardWriter: item.pasteboardItem(scope: scope))
        dragItem.setDraggingFrame(
            NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1),
            contents: Self.transparentDragImage
        )
        let session = beginDraggingSession(with: [dragItem], event: sessionEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func setSplitDropShieldActive(_ isActive: Bool) {
        splitDropShieldHandler?(isActive)
    }
}
