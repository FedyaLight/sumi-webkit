//
//  ToastView.swift
//  Sumi
//
//  Unified toast container component with standardized FindBar-style styling.
//

import SwiftUI

/// A reusable toast container that provides standardized visual styling.
/// Use with `.transition(.toast)` and `.animation(.smooth(duration: 0.25), value: condition)` in parent.
struct ToastView<Content: View>: View {
    let content: Content
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .fixedSize(horizontal: true, vertical: false)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
    }

    private var backgroundColor: Color {
        tokens.toastBackground
    }

    private var borderColor: Color {
        tokens.toastBorder
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

/// Custom toast transition matching FindBar animation exactly (opacity + blur)
extension AnyTransition {
    static var toast: AnyTransition {
        .modifier(
            active: ToastTransitionModifier(opacity: 0, blur: 8),
            identity: ToastTransitionModifier(opacity: 1, blur: 0)
        )
    }
}

private struct ToastTransitionModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
    }
}

// MARK: - Toast Content Helpers

/// Standard icon + text toast content with the default icon styling
struct ToastContent: View {
    let icon: String
    let text: String
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.toastPrimaryText)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(tokens.toastIconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tokens.toastBorder, lineWidth: 1)
                }

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.toastPrimaryText)
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

/// Multi-line toast content for showing a title with a subtitle
struct ToastContentWithSubtitle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.toastPrimaryText)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(tokens.toastIconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tokens.toastBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.toastPrimaryText)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.toastSecondaryText)
            }
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
