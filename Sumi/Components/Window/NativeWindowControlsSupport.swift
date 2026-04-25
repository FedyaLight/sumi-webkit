import AppKit
import ObjectiveC.runtime

struct NativeWindowControlsMetrics: Equatable {
    static let fallbackHostedSize = NSSize(width: 60, height: 18)

    let buttonFrames: [NSWindow.ButtonType: NSRect]
    let buttonGroupRect: NSRect
    let normalizedButtonFrames: [NSWindow.ButtonType: NSRect]

    init(
        buttonFrames: [NSWindow.ButtonType: NSRect],
        buttonGroupRect: NSRect
    ) {
        let resolvedGroupRect = buttonGroupRect.isNull ? .zero : buttonGroupRect

        self.buttonFrames = buttonFrames
        self.buttonGroupRect = resolvedGroupRect
        self.normalizedButtonFrames = buttonFrames.mapValues { frame in
            frame.offsetBy(
                dx: -resolvedGroupRect.minX,
                dy: -resolvedGroupRect.minY
            )
        }
    }

    var buttonGroupSize: NSSize {
        buttonGroupRect.size
    }

    var buttonGroupWidth: CGFloat {
        max(buttonGroupSize.width, 0)
    }
}

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"

    static func identifier(for type: NSWindow.ButtonType) -> String {
        switch type {
        case .closeButton:
            return closeButton
        case .miniaturizeButton:
            return minimizeButton
        case .zoomButton:
            return zoomButton
        default:
            return "browser-window-control-\(type.rawValue)"
        }
    }
}

enum NativeWindowControlsLayoutMode: Equatable {
    case nativeGroupCenteredY(leadingInset: CGFloat)
    case compact(spacing: CGFloat)
}

@MainActor
final class NativeWindowControlsHostController {
    let buttonTypes: [NSWindow.ButtonType]
    private(set) var layoutMode: NativeWindowControlsLayoutMode

    private weak var window: NSWindow?
    private weak var nativeTitlebarView: NSView?
    private weak var preferredHostView: NSView?
    private var hasCompletedHostedLayout = false
    private var hostedValidationObservers: [NSObjectProtocol] = []
    private var hostedPreDisplayValidationObserver: CFRunLoopObserver?
    private var isHostedValidationScheduled = false
    private var isApplyingHostedLayout = false
    private let hostedFrameTolerance: CGFloat = 0.5

    private(set) var cachedMetrics: NativeWindowControlsMetrics?

    init(
        window: NSWindow,
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes,
        layoutMode: NativeWindowControlsLayoutMode = .nativeGroupCenteredY(leadingInset: 0)
    ) {
        self.window = window
        self.buttonTypes = buttonTypes
        self.layoutMode = layoutMode
        nativeTitlebarView = window.titlebarView
        refreshNativeMetricsIfAvailable()
    }

    var hostedControlStripSize: NSSize {
        let metrics = cachedMetrics ?? window?.cachedNativeWindowControlsMetrics

        switch layoutMode {
        case .nativeGroupCenteredY(let leadingInset):
            let size = metrics?.buttonGroupSize ?? NativeWindowControlsMetrics.fallbackHostedSize
            return NSSize(
                width: size.width + leadingInset,
                height: size.height
            )
        case .compact(let spacing):
            let buttonFrames = buttonTypes.compactMap { metrics?.buttonFrames[$0] }
            guard buttonFrames.isEmpty == false else {
                return NativeWindowControlsMetrics.fallbackHostedSize
            }

            let totalButtonWidth = buttonFrames.reduce(CGFloat.zero) { partialResult, frame in
                partialResult + frame.width
            }
            let spacingWidth = spacing * CGFloat(max(buttonFrames.count - 1, 0))
            let maxHeight = buttonFrames.reduce(CGFloat.zero) { partialResult, frame in
                max(partialResult, frame.height)
            }
            return NSSize(
                width: max(totalButtonWidth + spacingWidth, NativeWindowControlsMetrics.fallbackHostedSize.width),
                height: max(maxHeight, NativeWindowControlsMetrics.fallbackHostedSize.height)
            )
        }
    }

    var hostedControlStripWidth: CGFloat {
        ceil(hostedControlStripSize.width)
    }

    func setLayoutMode(_ layoutMode: NativeWindowControlsLayoutMode) {
        guard self.layoutMode != layoutMode else { return }

        self.layoutMode = layoutMode
        if let preferredHostView {
            claimButtons(into: preferredHostView, refreshMetrics: false)
        }
    }

    func setPreferredHostView(_ hostView: NSView?) {
        let previousHostView = preferredHostView
        preferredHostView = hostView

        if let hostView {
            claimButtons(into: hostView, refreshMetrics: hasCompletedHostedLayout == false)
        } else {
            restoreButtonsToTitlebar(excluding: previousHostView)
        }
    }

    func releaseHostViewIfNeeded(_ hostView: NSView) {
        guard preferredHostView === hostView || buttonsAreHosted(in: hostView) else {
            return
        }

        if preferredHostView === hostView {
            preferredHostView = nil
        }

        restoreButtonsToTitlebar(excluding: hostView)
    }

    func layoutHostedButtonsIfNeeded(in hostView: NSView) {
        guard preferredHostView === hostView else { return }
        claimButtons(into: hostView, refreshMetrics: hasCompletedHostedLayout == false)
    }

    func handleWindowGeometryChange() {
        guard let preferredHostView else {
            refreshNativeMetricsIfAvailable()
            return
        }

        claimButtons(into: preferredHostView, refreshMetrics: false)
    }

    func handleEffectiveAppearanceChange() {
        guard let window else { return }

        if let preferredHostView {
            claimButtons(into: preferredHostView, refreshMetrics: false)
            enforceHostedLayoutIfNeeded()
            scheduleHostedLayoutValidation()
        } else {
            nativeTitlebarView = window.refreshCachedNativeWindowControlsTitlebarView(
                requiring: buttonTypes
            )
                ?? nativeTitlebarView
            refreshNativeMetricsIfAvailable()
        }
    }

    func enforceHostedLayoutIfNeeded() {
        guard let preferredHostView, let window else { return }

        if hostedButtonsNeedRepair(in: preferredHostView, window: window) {
            claimButtons(into: preferredHostView, refreshMetrics: false)
        }
    }

    func buttonsAreHosted(in hostView: NSView) -> Bool {
        guard let window else { return false }

        return buttonTypes.contains { type in
            window.standardWindowButton(type)?.superview === hostView
        }
    }

    private func claimButtons(into hostView: NSView, refreshMetrics: Bool) {
        guard let window else { return }

        window.restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        if refreshMetrics {
            refreshNativeMetricsIfAvailable(excluding: hostView)
        } else if cachedMetrics == nil,
                  let cachedMetrics = window.cachedNativeWindowControlsMetrics {
            self.cachedMetrics = cachedMetrics
        }

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview !== hostView {
                button.removeFromSuperview()
                hostView.addSubview(button)
            }
        }

        removeHostedValidationObservers()
        isApplyingHostedLayout = true
        layoutButtons(in: hostView, window: window)
        isApplyingHostedLayout = false
        installHostedValidationObservers(in: hostView, window: window)
        hasCompletedHostedLayout = true
    }

    private func restoreButtonsToTitlebar(excluding excludedSuperview: NSView? = nil) {
        removeHostedValidationObservers()

        guard let window,
              let nativeTitlebarView = window.refreshCachedNativeWindowControlsTitlebarView(
                excluding: excludedSuperview,
                requiring: buttonTypes
              )
                ?? nativeTitlebarView
                ?? window.titlebarView
        else {
            return
        }

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview !== nativeTitlebarView {
                button.removeFromSuperview()
                nativeTitlebarView.addSubview(button)
            }

            if let frame = cachedMetrics?.buttonFrames[type] {
                button.frame = frame
            }
        }

        window.prepareNativeWindowControlsForBrowserChrome(buttonTypes: buttonTypes)
        refreshNativeMetricsIfAvailable()
    }

    private func refreshNativeMetricsIfAvailable(excluding excludedSuperview: NSView? = nil) {
        guard let window else { return }

        nativeTitlebarView = window.refreshCachedNativeWindowControlsTitlebarView(
            excluding: excludedSuperview
        )
            ?? nativeTitlebarView
            ?? window.titlebarView

        if let metrics = window.captureNativeWindowControlsMetricsIfButtonsInTitlebar(
            for: buttonTypes,
            excluding: excludedSuperview
        ) {
            cachedMetrics = metrics
            window.cachedNativeWindowControlsMetrics = metrics
        } else if let cachedMetrics = window.cachedNativeWindowControlsMetrics {
            self.cachedMetrics = cachedMetrics
        }
    }

    private func layoutButtons(in hostView: NSView, window: NSWindow) {
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let expectedFrame = expectedHostedFrame(for: type, in: hostView, window: window)
            else { continue }

            button.isBordered = false
            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = expectedFrame
        }
    }

    private func expectedHostedFrame(
        for type: NSWindow.ButtonType,
        in hostView: NSView,
        window: NSWindow
    ) -> NSRect? {
        guard let button = window.standardWindowButton(type) else { return nil }

        let metrics = cachedMetrics ?? window.cachedNativeWindowControlsMetrics
        let containerHeight = boundsHeight(for: hostView, fallback: hostedControlStripSize.height)

        switch layoutMode {
        case .nativeGroupCenteredY(let leadingInset):
            let groupSize = metrics?.buttonGroupSize ?? NativeWindowControlsMetrics.fallbackHostedSize
            let groupOriginY = floor((containerHeight - groupSize.height) / 2)
            let normalizedFrame = metrics?.normalizedButtonFrames[type]
                ?? NSRect(origin: .zero, size: fallbackButtonSize(for: button))
            return normalizedFrame.offsetBy(dx: leadingInset, dy: groupOriginY)

        case .compact(let spacing):
            var xOffset: CGFloat = 0

            for currentType in buttonTypes {
                guard let currentButton = window.standardWindowButton(currentType) else { continue }

                let size = metrics?.buttonFrames[currentType]?.size
                    ?? fallbackButtonSize(for: currentButton)
                let frame = NSRect(
                    origin: NSPoint(
                        x: xOffset,
                        y: floor((containerHeight - size.height) / 2)
                    ),
                    size: size
                )

                if currentType == type {
                    return frame
                }

                xOffset += size.width + spacing
            }

            return nil
        }
    }

    private func installHostedValidationObservers(in hostView: NSView, window: NSWindow) {
        removeHostedValidationObservers()

        hostedValidationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: nil
            ) { [weak self] _ in
                self?.performHostedValidationFromNotification(immediate: true)
            }
        )

        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            button.postsFrameChangedNotifications = true
            hostedValidationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: button,
                    queue: nil
                ) { [weak self] _ in
                    self?.performHostedValidationFromNotification(immediate: true)
                }
            )
        }

        installHostedPreDisplayValidationObserver()
    }

    private nonisolated func performHostedValidationFromNotification(immediate: Bool) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if immediate {
                    handleHostedButtonFrameChange()
                } else {
                    scheduleHostedLayoutValidation()
                }
            }
        } else {
            Task { @MainActor [weak self] in
                if immediate {
                    self?.handleHostedButtonFrameChange()
                } else {
                    self?.scheduleHostedLayoutValidation()
                }
            }
        }
    }

    private func removeHostedValidationObservers() {
        for observer in hostedValidationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        hostedValidationObservers.removeAll()

        if let hostedPreDisplayValidationObserver {
            CFRunLoopRemoveObserver(
                CFRunLoopGetMain(),
                hostedPreDisplayValidationObserver,
                .commonModes
            )
            self.hostedPreDisplayValidationObserver = nil
        }

        isHostedValidationScheduled = false
    }

    private func installHostedPreDisplayValidationObserver() {
        guard hostedPreDisplayValidationObserver == nil else { return }

        let activities = CFRunLoopActivity.beforeWaiting.rawValue
            | CFRunLoopActivity.exit.rawValue
        guard let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            activities,
            true,
            CFIndex.max,
            { [weak self] _, _ in
                self?.performHostedValidationFromNotification(immediate: true)
            }
        ) else {
            return
        }

        hostedPreDisplayValidationObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func scheduleHostedLayoutValidation() {
        guard preferredHostView != nil,
              isHostedValidationScheduled == false
        else { return }

        isHostedValidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isHostedValidationScheduled = false
            self.enforceHostedLayoutIfNeeded()
        }
    }

    private func handleHostedButtonFrameChange() {
        guard isApplyingHostedLayout == false else { return }

        enforceHostedLayoutIfNeeded()
    }

    private func hostedButtonsNeedRepair(in hostView: NSView, window: NSWindow) -> Bool {
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type),
                  let expectedFrame = expectedHostedFrame(for: type, in: hostView, window: window)
            else {
                return true
            }

            if button.superview !== hostView {
                return true
            }

            if button.frame.isApproximatelyEqual(to: expectedFrame, tolerance: hostedFrameTolerance) == false {
                return true
            }
        }

        return false
    }

    private func boundsHeight(for hostView: NSView, fallback: CGFloat) -> CGFloat {
        if hostView.bounds.height > 0 {
            return hostView.bounds.height
        }

        return max(fallback, NativeWindowControlsMetrics.fallbackHostedSize.height)
    }

    private func fallbackButtonSize(for button: NSButton) -> NSSize {
        button.bounds.size == .zero
            ? NSSize(width: 14, height: 14)
            : button.bounds.size
    }
}

private extension NSRect {
    func isApproximatelyEqual(to other: NSRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

private enum NativeWindowControlsAssociatedKeys {
    static var titlebarView: UInt8 = 0
    static var cachedMetrics: UInt8 = 0
    static var hostController: UInt8 = 0
}

@MainActor
extension NSWindow {
    var titlebarView: NSView? {
        if let cached = cachedNativeWindowControlsTitlebarView {
            return cached
        }

        return refreshCachedNativeWindowControlsTitlebarView()
    }

    @discardableResult
    func refreshCachedNativeWindowControlsTitlebarView(
        excluding excludedSuperview: NSView? = nil,
        requiring buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) -> NSView? {
        if let resolved = trustedNativeWindowControlsTitlebarSuperview(
            excluding: excludedSuperview,
            requiring: buttonTypes
        ) {
            objc_setAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.titlebarView,
                resolved,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            return resolved
        }

        return cachedNativeWindowControlsTitlebarView
    }

    private var cachedNativeWindowControlsTitlebarView: NSView? {
        guard let cached = objc_getAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.titlebarView
        ) as? NSView else {
            return nil
        }

        return cached.window === self ? cached : nil
    }

    private func trustedNativeWindowControlsTitlebarSuperview(
        excluding excludedSuperview: NSView?,
        requiring buttonTypes: [NSWindow.ButtonType]
    ) -> NSView? {
        guard let resolved = standardWindowButton(.closeButton)?.superview,
              resolved.window === self,
              isRejectedNativeWindowControlsTitlebarCandidate(
                resolved,
                excluding: excludedSuperview
              ) == false
        else {
            return nil
        }

        for type in buttonTypes {
            guard standardWindowButton(type)?.superview === resolved else {
                return nil
            }
        }

        return resolved
    }

    private func isRejectedNativeWindowControlsTitlebarCandidate(
        _ candidate: NSView,
        excluding excludedSuperview: NSView?
    ) -> Bool {
        if let excludedSuperview,
           candidate === excludedSuperview || candidate.isDescendant(of: excludedSuperview) {
            return true
        }

        if let contentView,
           candidate === contentView || candidate.isDescendant(of: contentView) {
            return true
        }

        return false
    }

    var cachedNativeWindowControlsMetrics: NativeWindowControlsMetrics? {
        get {
            objc_getAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.cachedMetrics
            ) as? NativeWindowControlsMetrics
        }
        set {
            objc_setAssociatedObject(
                self,
                &NativeWindowControlsAssociatedKeys.cachedMetrics,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func browserChromeNativeWindowControlsHostController(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes,
        layoutMode: NativeWindowControlsLayoutMode = .nativeGroupCenteredY(
            leadingInset: SidebarChromeMetrics.windowControlsLeadingInset
        )
    ) -> NativeWindowControlsHostController {
        if let cached = objc_getAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.hostController
        ) as? NativeWindowControlsHostController {
            cached.setLayoutMode(layoutMode)
            return cached
        }

        let controller = NativeWindowControlsHostController(
            window: self,
            buttonTypes: buttonTypes,
            layoutMode: layoutMode
        )
        objc_setAssociatedObject(
            self,
            &NativeWindowControlsAssociatedKeys.hostController,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return controller
    }

    func prepareNativeWindowControlsForBrowserChrome(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        guard let titlebarView else { return }

        restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        titlebarView.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()
    }

    func restoreNativeWindowButtonVisibility(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = false
            button.alphaValue = 1
            button.isEnabled = true
            button.setAccessibilityIdentifier(
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
        }
    }

    func captureNativeWindowControlsMetricsIfButtonsInTitlebar(
        for buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes,
        excluding excludedSuperview: NSView? = nil
    ) -> NativeWindowControlsMetrics? {
        guard let titlebarView = refreshCachedNativeWindowControlsTitlebarView(
            excluding: excludedSuperview,
            requiring: buttonTypes
        ) else { return nil }

        for type in buttonTypes {
            guard let button = standardWindowButton(type),
                  button.superview === titlebarView
            else {
                return nil
            }
        }

        restoreNativeWindowButtonVisibility(buttonTypes: buttonTypes)
        titlebarView.needsLayout = true
        titlebarView.layoutSubtreeIfNeeded()

        var buttonFrames: [NSWindow.ButtonType: NSRect] = [:]
        var buttonGroupRect: NSRect = .null

        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { return nil }
            let frame = button.frame
            buttonFrames[type] = frame
            buttonGroupRect = buttonGroupRect.isNull ? frame : buttonGroupRect.union(frame)
        }

        let metrics = NativeWindowControlsMetrics(
            buttonFrames: buttonFrames,
            buttonGroupRect: buttonGroupRect
        )
        cachedNativeWindowControlsMetrics = metrics
        return metrics
    }

    var isReadyForBrowserChromeNativeWindowControls: Bool {
        guard toolbar?.identifier == SumiBrowserChromeConfiguration.toolbarIdentifier,
              titlebarView != nil
        else {
            return false
        }

        return SumiBrowserChromeConfiguration.buttonTypes.allSatisfy { type in
            standardWindowButton(type) != nil
        }
    }
}
