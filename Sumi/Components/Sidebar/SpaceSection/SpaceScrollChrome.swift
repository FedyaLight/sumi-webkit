//
//  SpaceScrollChrome.swift
//  Sumi
//

import SwiftUI
import AppKit

extension SpaceView {
    var mainContentContainer: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 8) {
                pinnedTabsSection

                VStack(spacing: 8) {
                    regularTabsSection
                }
            }
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            .background {
                SidebarTabListScrollRegistrationViewRepresentable(isEnabled: isInteractive)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("space-view-scroll-\(space.id.uuidString)")
        .scrollIndicators(.visible, axes: .vertical)
        .contentShape(Rectangle())
        .mask(SidebarTabListVerticalFadeMask())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarTabListVerticalFadeMask: View {
    private let fadeHeight: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)

            Color.white

            LinearGradient(
                colors: [.white, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
        }
    }
}

private struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> SidebarTabListScrollRegistrationView {
        SidebarTabListScrollRegistrationView()
    }

    func updateNSView(_ nsView: SidebarTabListScrollRegistrationView, context: Context) {
        nsView.isRegistrationEnabled = isEnabled
        nsView.scheduleRegistrationSync()
    }

    static func dismantleNSView(_ nsView: SidebarTabListScrollRegistrationView, coordinator: ()) {
        nsView.unregisterScrollView()
    }
}

private final class SidebarTabListScrollRegistrationView: NSView {
    var isRegistrationEnabled = true {
        didSet {
            guard isRegistrationEnabled != oldValue else { return }
            syncRegistration()
        }
    }

    private weak var registeredScrollView: NSScrollView?

    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleRegistrationSync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleRegistrationSync()
    }

    func scheduleRegistrationSync() {
        DispatchQueue.main.async { [weak self] in
            self?.syncRegistration()
        }
    }

    func unregisterScrollView() {
        guard let registeredScrollView else { return }
        SidebarTabListDragAutoscrollRegistry.shared.unregister(registeredScrollView)
        self.registeredScrollView = nil
    }

    private func syncRegistration() {
        guard isRegistrationEnabled,
              window != nil,
              let scrollView = enclosingScrollView else {
            unregisterScrollView()
            return
        }

        guard registeredScrollView !== scrollView else { return }
        unregisterScrollView()
        SidebarTabListDragAutoscrollRegistry.shared.register(scrollView)
        registeredScrollView = scrollView
    }
}
