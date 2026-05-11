import AppKit
import SwiftUI
import WebKit

struct SumiNavigationToolbarControlState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var canReload: Bool
    var isLoading: Bool

    var reloadAssetName: String {
        isLoading ? "Stop" : "Refresh"
    }

    var reloadAccessibilityTitle: String {
        isLoading ? "Stop" : "Reload"
    }

    var reloadTooltip: String {
        isLoading ? "Stop loading" : "Reload"
    }
}

struct SumiNavigationToolbarTheme {
    let tintColor: NSColor
    let hoverColor: NSColor
    let mouseDownColor: NSColor
    let disabledAlpha: CGFloat

    init(tokens: ChromeThemeTokens, colorScheme: ColorScheme) {
        let tint = NSColor(tokens.primaryText).usingColorSpace(.displayP3)
            ?? NSColor(tokens.primaryText).usingColorSpace(.sRGB)
            ?? .labelColor

        tintColor = tint
        hoverColor = tint.withAlphaComponent(colorScheme == .dark ? 0.16 : 0.10)
        mouseDownColor = tint.withAlphaComponent(colorScheme == .dark ? 0.24 : 0.16)
        disabledAlpha = 0.34
    }
}

struct SumiNavigationToolbarControls: NSViewRepresentable {
    let state: SumiNavigationToolbarControlState
    let theme: SumiNavigationToolbarTheme
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let tab: Tab?
    let activeWebView: WKWebView?
    let goBack: () -> Void
    let goForward: () -> Void
    let reloadOrStop: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SumiNavigationToolbarControlsView {
        let view = SumiNavigationToolbarControlsView(
            buttonSize: SidebarChromeMetrics.navigationButtonSize,
            spacing: SidebarChromeMetrics.controlSpacing
        )
        configure(view.backButton, control: .back, coordinator: context.coordinator)
        configure(view.forwardButton, control: .forward, coordinator: context.coordinator)
        configure(view.reloadButton, control: .reload, coordinator: context.coordinator)
        installHistoryMenus(on: view, coordinator: context.coordinator)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: SumiNavigationToolbarControlsView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateHistoryDelegates()

        updateButton(
            nsView.backButton,
            assetName: "Back",
            title: "Go Back",
            tooltip: "Go Back",
            isEnabled: state.canGoBack
        )
        updateButton(
            nsView.forwardButton,
            assetName: "Forward",
            title: "Go Forward",
            tooltip: "Go Forward",
            isEnabled: state.canGoForward
        )
        updateButton(
            nsView.reloadButton,
            assetName: state.reloadAssetName,
            title: state.reloadAccessibilityTitle,
            tooltip: state.reloadTooltip,
            isEnabled: state.canReload || state.isLoading
        )
    }

    private func configure(
        _ button: MouseOverButton,
        control: Coordinator.Control,
        coordinator: Coordinator
    ) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.sendAction(on: [.leftMouseUp, .otherMouseDown])
        button.target = coordinator
        button.action = #selector(Coordinator.buttonAction(_:))
        button.tag = control.rawValue
        button.cornerRadius = 6
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: SidebarChromeMetrics.navigationButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: SidebarChromeMetrics.navigationButtonSize).isActive = true
    }

    private func installHistoryMenus(
        on view: SumiNavigationToolbarControlsView,
        coordinator: Coordinator
    ) {
        let backMenu = NSMenu()
        backMenu.autoenablesItems = false
        backMenu.delegate = coordinator.backMenuDelegate
        install(menu: backMenu, on: view.backButton)

        let forwardMenu = NSMenu()
        forwardMenu.autoenablesItems = false
        forwardMenu.delegate = coordinator.forwardMenuDelegate
        install(menu: forwardMenu, on: view.forwardButton)
    }

    private func install(menu: NSMenu, on button: MouseOverButton) {
        button.menu = menu
    }

    private func updateButton(
        _ button: MouseOverButton,
        assetName: String,
        title: String,
        tooltip: String,
        isEnabled: Bool
    ) {
        button.image = Self.image(named: assetName)
        button.normalTintColor = theme.tintColor
        button.mouseOverTintColor = theme.tintColor
        button.mouseDownTintColor = theme.tintColor
        button.mouseOverColor = theme.hoverColor
        button.mouseDownColor = theme.mouseDownColor
        button.toolTip = tooltip
        button.setAccessibilityTitle(title)
        button.isEnabled = isEnabled
        button.alphaValue = isEnabled ? 1 : theme.disabledAlpha
    }

    private static func image(named assetName: String) -> NSImage? {
        let image = NSImage(named: NSImage.Name(assetName)) ?? fallbackImage(named: assetName)
        image?.isTemplate = true
        return image
    }

    private static func fallbackImage(named assetName: String) -> NSImage? {
        let systemName: String
        switch assetName {
        case "Back":
            systemName = "chevron.left"
        case "Forward":
            systemName = "chevron.right"
        case "Stop":
            systemName = "xmark"
        default:
            systemName = "arrow.clockwise"
        }
        return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    @MainActor
    final class Coordinator: NSObject {
        enum Control: Int {
            case back
            case forward
            case reload
        }

        var parent: SumiNavigationToolbarControls
        let backMenuDelegate = SumiNavigationHistoryMenuDelegate(direction: .back)
        let forwardMenuDelegate = SumiNavigationHistoryMenuDelegate(direction: .forward)

        init(parent: SumiNavigationToolbarControls) {
            self.parent = parent
            super.init()
            updateHistoryDelegates()
        }

        func updateHistoryDelegates() {
            configure(backMenuDelegate, direction: .back)
            configure(forwardMenuDelegate, direction: .forward)
        }

        @objc func buttonAction(_ sender: MouseOverButton) {
            guard let control = Control(rawValue: sender.tag) else { return }

            switch control {
            case .back:
                parent.goBack()
            case .forward:
                parent.goForward()
            case .reload:
                parent.reloadOrStop()
            }
        }

        private func configure(
            _ delegate: SumiNavigationHistoryMenuDelegate,
            direction: SumiNavigationHistoryDirection
        ) {
            delegate.direction = direction
            delegate.browserManager = parent.browserManager
            delegate.windowState = parent.windowState
            delegate.tabProvider = { [weak self] in
                self?.parent.tab
            }
            delegate.webViewProvider = { [weak self] in
                self?.parent.activeWebView
            }
        }
    }
}

final class SumiNavigationToolbarControlsView: NSStackView {
    let backButton = SumiNavigationLongPressButton(frame: .zero)
    let forwardButton = SumiNavigationLongPressButton(frame: .zero)
    let reloadButton = MouseOverButton(frame: .zero)

    init(buttonSize: CGFloat, spacing: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: buttonSize * 3 + spacing * 2, height: buttonSize))
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        self.spacing = spacing
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(backButton)
        addArrangedSubview(forwardButton)
        addArrangedSubview(reloadButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SumiNavigationLongPressButton: MouseOverButton {
    private var menuTimer: Timer?
    private var mouseUpEventSnapshot: SumiNavigationMouseUpEventSnapshot?

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else {
            super.rightMouseDown(with: event)
            return
        }

        isMouseDown = true
        displayMenu(menu)
        isMouseDown = false
    }

    override func mouseDown(with event: NSEvent) {
        resetMenuTimer()

        guard menu != nil else {
            super.mouseDown(with: event)
            return
        }

        isMouseDown = true

        mouseUpEventSnapshot = SumiNavigationMouseUpEventSnapshot(event: event)
        let timer = Timer(
            timeInterval: 0.3,
            target: self,
            selector: #selector(longPressTimerFired(_:)),
            userInfo: nil,
            repeats: false
        )
        menuTimer = timer
        RunLoop.current.add(timer, forMode: .eventTracking)

        trackMouseEvents(previousEvent: event)

        resetMenuTimer()
        isMouseDown = false
    }

    @objc private func longPressTimerFired(_ timer: Timer) {
        let mouseUpEventSnapshot = mouseUpEventSnapshot
        displayInstalledMenu()
        guard let mouseUpEvent = mouseUpEventSnapshot?.makeEvent() else { return }
        window?.postEvent(mouseUpEvent, atStart: true)
    }

    private func trackMouseEvents(previousEvent: NSEvent) {
        while let event = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch event.type {
            case .leftMouseDragged:
                guard menuTimer != nil else { return }
                guard isMouseLocationVerticallyInside(event.locationInWindow) else { return }
                guard Int(event.locationInWindow.x) != Int(previousEvent.locationInWindow.x),
                      Int(event.locationInWindow.y) != Int(previousEvent.locationInWindow.y)
                else { break }

                if let menu {
                    displayMenu(menu)
                }
                return

            case .leftMouseUp:
                guard menuTimer != nil,
                      bounds.contains(convert(event.locationInWindow, from: nil))
                else { return }

                sendAction(action, to: target)
                return

            default:
                return
            }
        }
    }

    private func isMouseLocationVerticallyInside(_ locationInWindow: NSPoint) -> Bool {
        let location = convert(locationInWindow, from: nil)
        return (bounds.minX...bounds.maxX).contains(location.x)
    }

    private func displayMenu(_ menu: NSMenu) {
        resetMenuTimer()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    private func displayInstalledMenu() {
        guard let menu else { return }
        displayMenu(menu)
    }

    private func resetMenuTimer() {
        menuTimer?.invalidate()
        menuTimer = nil
        mouseUpEventSnapshot = nil
    }
}

private struct SumiNavigationMouseUpEventSnapshot: Sendable {
    let locationX: CGFloat
    let locationY: CGFloat
    let modifierFlagsRawValue: UInt
    let timestamp: TimeInterval
    let windowNumber: Int
    let eventNumber: Int
    let clickCount: Int
    let pressure: Float

    init(event: NSEvent) {
        locationX = event.locationInWindow.x
        locationY = event.locationInWindow.y
        modifierFlagsRawValue = event.modifierFlags.rawValue
        timestamp = event.timestamp
        windowNumber = event.windowNumber
        eventNumber = event.eventNumber
        clickCount = event.clickCount
        pressure = event.pressure
    }

    func makeEvent() -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: locationX, y: locationY),
            modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue),
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: pressure
        )
    }
}
