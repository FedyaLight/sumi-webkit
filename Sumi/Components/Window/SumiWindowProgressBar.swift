//
//  SumiWindowProgressBar.swift
//  Sumi
//

import AppKit
import Combine
import SumiDomain
import SwiftUI

struct SumiWindowProgressBar: View {
    let tab: Tab
    let glanceSession: GlanceSession?
    let resolveWorkspaceTheme: (Tab) -> WorkspaceTheme

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tabIsLoading = false
    @State private var glanceIsLoading = false

    init(
        tab: Tab,
        glanceSession: GlanceSession? = nil,
        resolveWorkspaceTheme: @escaping (Tab) -> WorkspaceTheme
    ) {
        self.tab = tab
        self.glanceSession = glanceSession
        self.resolveWorkspaceTheme = resolveWorkspaceTheme
    }

    var body: some View {
        SumiProgressBarRepresentable(
            isLoading: isLoading,
            accentColor: resolvedAccentColor,
            isDark: isSpaceThemeDark,
            reduceMotion: reduceMotion
        )
        .id(loadingSourceID)
        .allowsHitTesting(false)
        .onAppear(perform: syncLoadingState)
        .onChange(of: tab.id) { _, _ in
            syncLoadingState()
        }
        .onChange(of: glanceSession?.id) { _, _ in
            syncLoadingState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabLoadingStateDidChange)) { notification in
            guard let notificationTab = notification.object as? Tab,
                  notificationTab.id == tab.id
            else { return }

            syncLoadingState()
        }
        .onReceive(glanceLoadingPublisher) { isLoading in
            guard glanceIsLoading != isLoading else { return }
            glanceIsLoading = isLoading
        }
    }

    private var isLoading: Bool {
        glanceSession == nil ? tabIsLoading : glanceIsLoading
    }

    private var loadingSourceID: UUID {
        glanceSession?.id ?? tab.id
    }

    private var glanceLoadingPublisher: AnyPublisher<Bool, Never> {
        guard let glanceSession else {
            return Just(false).eraseToAnyPublisher()
        }
        return glanceSession.$isLoading
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var activeWorkspaceTheme: WorkspaceTheme {
        resolveWorkspaceTheme(tab)
    }

    private var resolvedAccentColor: Color {
        tabThemeContext.tokens(settings: sumiSettings).accent
    }

    private var globalColorScheme: ColorScheme {
        switch sumiSettings.windowSchemeMode {
        case .auto:
            return colorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var tabThemeContext: ResolvedThemeContext {
        windowState.resolvedThemeContext(
            for: activeWorkspaceTheme,
            global: globalColorScheme,
            settings: sumiSettings
        )
    }

    private var isSpaceThemeDark: Bool {
        ChromePageLoadingIndicatorStyle.isDarkTheme(
            workspaceTheme: activeWorkspaceTheme,
            fallbackColorScheme: globalColorScheme
        )
    }

    private func syncLoadingState() {
        tabIsLoading = tab.loadingState.isLoading
        glanceIsLoading = glanceSession?.isLoading ?? false
    }
}

private struct SumiProgressBarRepresentable: NSViewRepresentable {
    let isLoading: Bool
    let accentColor: Color
    let isDark: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SumiProgressBarView {
        SumiProgressBarView()
    }

    func updateNSView(_ nsView: SumiProgressBarView, context: Context) {
        nsView.update(
            isLoading: isLoading,
            accentColor: NSColor(accentColor),
            isDark: isDark,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleNSView(_ nsView: SumiProgressBarView, coordinator: Void) {
        nsView.prepareForRemoval()
    }
}

private final class SumiProgressBarView: NSView {
    private enum Metrics {
        static let compactWidth: CGFloat = 80
        static let expandedWidth: CGFloat = 160
        static let height: CGFloat = 4
        static let radius: CGFloat = 2
        static let sweepWidth: CGFloat = expandedWidth * 0.75
        static let longLoadDelay: TimeInterval = 3
        static let appearanceDuration: CFTimeInterval = 0.18
        static let settleDuration: CFTimeInterval = 0.3
        static let sweepDuration: CFTimeInterval = 1
    }

    private let railLayer = CALayer()
    private let sweepLayer = CALayer()

    private var isLoading = false
    private var isLongLoad = false
    private var currentAccentColor = NSColor.controlAccentColor
    private var isDarkTheme = false
    private var reduceMotion = false
    private var longLoadTimer: Timer?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        railLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func isAccessibilityElement() -> Bool {
        isLoading
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .progressIndicator
    }

    override func accessibilityLabel() -> String? {
        "Page loading"
    }

    func update(
        isLoading: Bool,
        accentColor: NSColor,
        isDark: Bool,
        reduceMotion: Bool
    ) {
        let loadingChanged = self.isLoading != isLoading
        let colorChanged = currentAccentColor != accentColor
            || isDarkTheme != isDark
        let motionPreferenceChanged = self.reduceMotion != reduceMotion

        self.isLoading = isLoading
        currentAccentColor = accentColor
        isDarkTheme = isDark
        self.reduceMotion = reduceMotion

        if colorChanged {
            updateColors()
        }

        if loadingChanged {
            isLoading ? startLoading() : stopLoading()
        } else if isLoading, motionPreferenceChanged {
            startLoading()
        }
    }

    func prepareForRemoval() {
        isLoading = false
        longLoadTimer?.invalidate()
        longLoadTimer = nil
        railLayer.removeAllAnimations()
        sweepLayer.removeAllAnimations()
    }

    private var shouldAnimate: Bool {
        !reduceMotion
    }

    private var fillColor: NSColor {
        ChromePageLoadingIndicatorStyle.fillColor(
            accentColor: currentAccentColor,
            isDarkTheme: isDarkTheme
        )
    }

    private var railColor: NSColor {
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if isDarkTheme {
            return .white.withAlphaComponent(increaseContrast ? 0.28 : 0.16)
        }

        return .black.withAlphaComponent(increaseContrast ? 0.24 : 0.12)
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        railLayer.bounds = CGRect(x: 0, y: 0, width: Metrics.compactWidth, height: Metrics.height)
        railLayer.cornerRadius = Metrics.radius
        railLayer.masksToBounds = true
        railLayer.opacity = 0

        sweepLayer.bounds = CGRect(x: 0, y: 0, width: Metrics.sweepWidth, height: Metrics.height)
        sweepLayer.cornerRadius = Metrics.radius
        sweepLayer.opacity = 0

        railLayer.addSublayer(sweepLayer)
        layer?.addSublayer(railLayer)
        updateColors()
    }

    private func updateColors() {
        performWithoutAnimation {
            railLayer.backgroundColor = (isLongLoad ? railColor : fillColor).cgColor
            sweepLayer.backgroundColor = fillColor.cgColor
        }
    }

    private func startLoading() {
        longLoadTimer?.invalidate()
        isLongLoad = false
        applyCompactPresentation()

        guard !reduceMotion else { return }

        let timer = Timer(
            timeInterval: Metrics.longLoadDelay,
            target: self,
            selector: #selector(enterLongLoad),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        longLoadTimer = timer
    }

    private func stopLoading() {
        longLoadTimer?.invalidate()
        longLoadTimer = nil

        let presentationOpacity = railLayer.presentation()?.opacity ?? railLayer.opacity
        let presentationTransform = railLayer.presentation()?.transform ?? railLayer.transform

        isLongLoad = false
        railLayer.removeAllAnimations()
        sweepLayer.removeAllAnimations()
        performWithoutAnimation {
            railLayer.opacity = 0
            railLayer.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            sweepLayer.opacity = 0
        }

        guard shouldAnimate else { return }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = presentationOpacity
        opacity.toValue = 0

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: presentationTransform)
        transform.toValue = NSValue(caTransform3D: railLayer.transform)

        let exit = CAAnimationGroup()
        exit.animations = [opacity, transform]
        exit.duration = Metrics.settleDuration
        exit.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        railLayer.add(exit, forKey: "exit")
    }

    private func applyCompactPresentation() {
        railLayer.removeAllAnimations()
        sweepLayer.removeAllAnimations()
        performWithoutAnimation {
            railLayer.bounds.size.width = Metrics.compactWidth
            railLayer.backgroundColor = fillColor.cgColor
            railLayer.opacity = 1
            railLayer.transform = CATransform3DIdentity
            sweepLayer.opacity = 0
        }

        guard shouldAnimate else { return }

        let appearanceOpacity = CABasicAnimation(keyPath: "opacity")
        appearanceOpacity.fromValue = 0
        appearanceOpacity.toValue = 1

        let appearanceTransform = CABasicAnimation(keyPath: "transform")
        appearanceTransform.fromValue = NSValue(
            caTransform3D: CATransform3DMakeScale(0.95, 0.95, 1)
        )
        appearanceTransform.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let appearance = CAAnimationGroup()
        appearance.animations = [appearanceOpacity, appearanceTransform]
        appearance.duration = Metrics.appearanceDuration
        appearance.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        railLayer.add(appearance, forKey: "appearance")

        let pulseOpacity = CABasicAnimation(keyPath: "opacity")
        pulseOpacity.fromValue = 1
        pulseOpacity.toValue = 0.6

        let pulseTransform = CABasicAnimation(keyPath: "transform")
        pulseTransform.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        pulseTransform.toValue = NSValue(
            caTransform3D: CATransform3DMakeScale(0.9, 0.9, 1)
        )

        let pulse = CAAnimationGroup()
        pulse.animations = [pulseOpacity, pulseTransform]
        pulse.duration = 1
        pulse.beginTime = railLayer.convertTime(CACurrentMediaTime(), from: nil)
            + Metrics.appearanceDuration
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        railLayer.add(pulse, forKey: "pulse")
    }

    @objc private func enterLongLoad() {
        longLoadTimer = nil
        guard isLoading, !reduceMotion else { return }

        let presentationBounds = railLayer.presentation()?.bounds ?? railLayer.bounds
        let presentationOpacity = railLayer.presentation()?.opacity ?? railLayer.opacity
        let presentationTransform = railLayer.presentation()?.transform ?? railLayer.transform
        let presentationBackground = railLayer.presentation()?.backgroundColor ?? railLayer.backgroundColor

        isLongLoad = true
        railLayer.removeAllAnimations()
        performWithoutAnimation {
            railLayer.bounds.size.width = Metrics.expandedWidth
            railLayer.backgroundColor = railColor.cgColor
            railLayer.opacity = 1
            railLayer.transform = CATransform3DIdentity
            sweepLayer.opacity = 0
        }

        guard shouldAnimate else { return }

        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: presentationBounds)
        bounds.toValue = NSValue(rect: railLayer.bounds)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = presentationOpacity
        opacity.toValue = 1

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: presentationTransform)
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let background = CABasicAnimation(keyPath: "backgroundColor")
        background.fromValue = presentationBackground
        background.toValue = railColor.cgColor

        let settle = CAAnimationGroup()
        settle.animations = [bounds, opacity, transform, background]
        settle.duration = Metrics.settleDuration
        settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        railLayer.add(settle, forKey: "settle")

        startSweep(after: Metrics.settleDuration)
    }

    private func startSweep(after delay: CFTimeInterval = 0) {
        let startX = -Metrics.sweepWidth / 2
        let endX = Metrics.expandedWidth + Metrics.sweepWidth / 2

        performWithoutAnimation {
            sweepLayer.position = CGPoint(x: endX, y: Metrics.height / 2)
            sweepLayer.opacity = 1
        }

        let position = CABasicAnimation(keyPath: "position.x")
        position.fromValue = startX
        position.toValue = endX
        position.duration = Metrics.sweepDuration
        position.beginTime = CACurrentMediaTime() + delay
        position.repeatCount = .infinity
        position.timingFunction = CAMediaTimingFunction(name: .linear)
        sweepLayer.add(position, forKey: "sweep")
    }

    private func performWithoutAnimation(_ action: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        action()
        CATransaction.commit()
    }
}
