//
//  ToastView.swift
//  Sumi
//
//  Lightweight browser feedback banners.
//

import SwiftUI

struct ToastView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .fixedSize(horizontal: true, vertical: false)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 5)
    }
}

extension AnyTransition {
    static var toast: AnyTransition {
        .modifier(
            active: ToastTransitionModifier(opacity: 0, y: -6, scale: 0.98),
            identity: ToastTransitionModifier(opacity: 1, y: 0, scale: 1)
        )
    }
}

private struct ToastTransitionModifier: ViewModifier {
    let opacity: Double
    let y: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: y)
            .scaleEffect(scale, anchor: .topTrailing)
    }
}

struct BrowserToastView: View {
    let toast: BrowserToast
    @Environment(KeyboardShortcutManager.self) private var shortcutManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToastView {
            HStack(spacing: 10) {
                Image(systemName: toast.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = toast.subtitle(shortcutManager: shortcutManager) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .transition(reduceMotion ? .opacity : .toast)
    }
}
