//
//  SumiWindowProgressBar.swift
//  Sumi
//

import AppKit
import Combine
import SwiftUI

struct SumiWindowProgressBar: View {
    let tab: Tab

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isLoading = false

    var body: some View {
        SumiProgressBarRepresentable(
            tab: tab,
            isLoading: isLoading,
            accentColor: resolvedAccentColor,
            isDark: isSpaceThemeDark,
            reduceMotion: reduceMotion
        )
        .id(tab.id)
        .allowsHitTesting(false)
        .onAppear(perform: syncLoadingState)
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabLoadingStateDidChange)) { notification in
            guard let notificationTab = notification.object as? Tab,
                  notificationTab.id == tab.id
            else { return }

            syncLoadingState()
        }
    }

    private var activeWorkspaceTheme: WorkspaceTheme {
        if let spaceId = tab.spaceId,
           let space = browserManager.space(for: spaceId) {
            return space.workspaceTheme
        }
        return windowState.workspaceTheme
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
        guard !activeWorkspaceTheme.gradientTheme.normalizedColors.isEmpty else {
            return globalColorScheme == .dark
        }

        let hex = activeWorkspaceTheme.gradientTheme.primaryColorHex
        return NSColor(Color(hex: hex)).themePerceivedLightness < 0.5
    }

    private func syncLoadingState() {
        isLoading = tab.loadingState.isLoading
    }
}

private struct SumiProgressBarRepresentable: NSViewRepresentable {
    let tab: Tab
    let isLoading: Bool
    let accentColor: Color
    let isDark: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SumiProgressBarView {
        let view = SumiProgressBarView()
        context.coordinator.bind(tab, to: view, isLoading: tab.loadingState.isLoading)
        return view
    }

    func updateNSView(_ nsView: SumiProgressBarView, context: Context) {
        context.coordinator.bind(tab, to: nsView, isLoading: isLoading)
        nsView.update(
            isLoading: isLoading,
            progress: tab.estimatedProgress,
            accentColor: NSColor(accentColor),
            isDark: isDark,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleNSView(_ nsView: SumiProgressBarView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    @MainActor
    final class Coordinator {
        private weak var view: SumiProgressBarView?
        private var tabId: UUID?
        private var progressCancellable: AnyCancellable?

        func bind(_ tab: Tab, to view: SumiProgressBarView, isLoading: Bool) {
            let targetChanged = tabId != tab.id || self.view !== view

            if !targetChanged, isLoading == (progressCancellable != nil) {
                return
            }

            tabId = tab.id
            self.view = view
            progressCancellable = nil
            view.setProgress(tab.estimatedProgress)

            guard isLoading else {
                return
            }

            progressCancellable = tab.$estimatedProgress
                .removeDuplicates { abs($0 - $1) < 0.01 }
                .throttle(for: .milliseconds(80), scheduler: RunLoop.main, latest: true)
                .sink { [weak view] progress in
                    MainActor.assumeIsolated {
                        view?.setProgress(progress)
                    }
                }
        }

        func unbind() {
            progressCancellable = nil
            tabId = nil
            view = nil
        }
    }
}

private final class SumiProgressBarView: NSView {
    private enum Metrics {
        static let width: CGFloat = 160
        static let height: CGFloat = 4
        static let radius: CGFloat = 2
    }

    private let railLayer = CALayer()
    private let fillLayer = CALayer()

    private var isLoading = false
    private var progress = 0.0
    private var currentAccentColor = NSColor.controlAccentColor
    private var isDarkTheme = false
    private var reduceMotion = false

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

    override func accessibilityValue() -> Any? {
        Int(normalizedProgress * 100)
    }

    func update(
        isLoading: Bool,
        progress: Double,
        accentColor: NSColor,
        isDark: Bool,
        reduceMotion: Bool
    ) {
        let loadingChanged = self.isLoading != isLoading
        let colorChanged = currentAccentColor != accentColor
            || isDarkTheme != isDark

        self.isLoading = isLoading
        self.progress = progress
        currentAccentColor = accentColor
        isDarkTheme = isDark
        self.reduceMotion = reduceMotion

        if colorChanged {
            updateColors()
        }

        updateFill(animated: isLoading && !loadingChanged)
        updateVisibility(animated: loadingChanged)
    }

    func setProgress(_ progress: Double) {
        self.progress = progress
        guard isLoading else { return }

        updateFill(animated: true)
    }

    private var normalizedProgress: Double {
        guard progress.isFinite else { return 0.05 }

        let clampedProgress = min(max(progress, 0.0), 1.0)
        return isLoading ? min(max(clampedProgress, 0.05), 0.95) : clampedProgress
    }

    private var shouldAnimate: Bool {
        guard let window else { return false }

        return !reduceMotion
            && !isHiddenOrHasHiddenAncestor
            && window.occlusionState.contains(.visible)
    }

    private var fillColor: NSColor {
        let contrastColor: NSColor = isDarkTheme ? .white : .black
        return currentAccentColor.blended(withFraction: 0.65, of: contrastColor) ?? contrastColor
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

        railLayer.bounds = CGRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height)
        railLayer.cornerRadius = Metrics.radius
        railLayer.masksToBounds = true
        railLayer.opacity = 0

        fillLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.position = CGPoint(x: 0, y: Metrics.height / 2)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: 0, height: Metrics.height)
        fillLayer.cornerRadius = Metrics.radius
        fillLayer.masksToBounds = true

        railLayer.addSublayer(fillLayer)
        layer?.addSublayer(railLayer)
        updateColors()
    }

    private func updateColors() {
        performWithoutAnimation {
            railLayer.backgroundColor = railColor.cgColor
            fillLayer.backgroundColor = fillColor.cgColor
        }
    }

    private func updateFill(animated: Bool) {
        let width = Metrics.width * normalizedProgress

        performLayerUpdate(animated: animated, duration: 0.12) {
            fillLayer.bounds.size.width = width
        }
    }

    private func updateVisibility(animated: Bool) {
        performLayerUpdate(animated: animated, duration: 0.16) {
            railLayer.opacity = isLoading ? 1 : 0
        }
    }

    private func performLayerUpdate(animated: Bool, duration: CFTimeInterval, _ action: () -> Void) {
        let shouldAnimate = animated && self.shouldAnimate

        CATransaction.begin()
        CATransaction.setDisableActions(!shouldAnimate)
        if shouldAnimate {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        action()
        CATransaction.commit()
    }

    private func performWithoutAnimation(_ action: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        action()
        CATransaction.commit()
    }
}
