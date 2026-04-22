//
//  SumiButtonStyle.swift
//  Sumi
//
//  Created by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct SumiButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let variant: Variant
    let role: ButtonRole?

    @State private var isHovering: Bool = false

    // MARK: - Constants

    private let cornerRadius: CGFloat = 14
    private let verticalPadding: CGFloat = 12
    private let horizontalPadding: CGFloat = 12

    // Hover effects
    private let hoverMixAmount: CGFloat = 0.2

    // Disabled state
    private let disabledOpacity: CGFloat = 0.3

    enum Variant {
        case secondary  // Regular button
        case primary    // Prominent button
    }

    // MARK: - Body

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            // Resolve a readable foreground and blend it into hover feedback.
            let baseColor = backgroundColor()
            let contrastingShade = contrastingTextColor(for: baseColor)
            let backgroundWithHover = baseColor.mix(with: contrastingShade, by: isHovering ? hoverMixAmount : 0)

            // Main button label with background
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(contrastingShade)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .background(backgroundWithHover)
                .clipShape(.rect(cornerRadius: cornerRadius))
        }
        .compositingGroup()
        .opacity(isEnabled ? 1.0 : disabledOpacity)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Helper Methods

    /// Returns the contrasting text color for the given background
    private func contrastingTextColor(for background: Color) -> Color {
        ThemeContrastResolver.contrastingShade(
            of: background,
            targetRatio: 2,
            directionPreference: .preferLight,
            minimumBlend: 0.6
        ) ?? textColor
    }

    /// Returns the base background color based on variant and role
    private func backgroundColor() -> Color {
        // Destructive role overrides variant colors
        if role == .destructive {
            return Color.red
        }

        switch variant {
        case .secondary:
            return tokens.buttonSecondaryBackground
        case .primary:
            return tokens.buttonPrimaryBackground
        }
    }

    /// Fallback text color when a computed contrast shade is unavailable.
    private var textColor: Color {
        switch variant {
        case .secondary:
            return tokens.primaryText
        case .primary:
            return Color.white
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == SumiButtonStyle {
    static var sumiButton: SumiButtonStyle {
        SumiButtonStyle(variant: .secondary, role: nil)
    }

    static func sumiButton(role: ButtonRole?) -> SumiButtonStyle {
        SumiButtonStyle(variant: .secondary, role: role)
    }

    static var sumiButtonProminent: SumiButtonStyle {
        SumiButtonStyle(variant: .primary, role: nil)
    }

    static func sumiButtonProminent(role: ButtonRole?) -> SumiButtonStyle {
        SumiButtonStyle(variant: .primary, role: role)
    }
}

#Preview {
    let colors = [Color.blue, Color.purple, Color.green, Color.orange, Color.pink, Color.red]

    return ScrollView {
        VStack(spacing: 40) {
            ForEach(colors, id: \.self) { color in
                ButtonPreviewSection(color: color)
            }
        }
        .padding()
    }
    .frame(width: 390, height: 1000)
}

private struct ButtonPreviewSection: View {
    let color: Color

    var body: some View {
        VStack(spacing: 20) {
            Text(colorName)
                .font(.headline)
                .foregroundStyle(.secondary)

            buttonStack
        }
        .padding()
        .background(.background.opacity(0.5))
        .cornerRadius(12)
        .environmentObject(makeColorManager())
    }

    private var colorName: String {
        color.description.capitalized
    }

    private func makeColorManager() -> WorkspaceThemeEditorPreview {
        let manager = WorkspaceThemeEditorPreview()
#if canImport(AppKit)
        let hex = color.toHexString(includeAlpha: true) ?? "#FFFFFFFF"
#else
        let hex = "#FFFFFFFF"
#endif
        let n1 = GradientNode(colorHex: hex, location: 0.0)
        let n2 = GradientNode(colorHex: hex, location: 1.0)
        let gradient = SpaceGradient(angle: 45.0, nodes: [n1, n2], grain: 0.05, opacity: 1.0)
        manager.setImmediate(gradient)
        return manager
    }

    private var buttonStack: some View {
        VStack(spacing: 20) {
            Button("Create Space", systemImage: "plus") {
                RuntimeDiagnostics.emit("Create")
            }
            .buttonStyle(.sumiButtonProminent)
            .background(.red)

            Button("Cancel") {
                RuntimeDiagnostics.emit("Cancel")
            }
            .buttonStyle(.sumiButton)

            Button("Delete", systemImage: "trash") {
                RuntimeDiagnostics.emit("Delete")
            }
            .buttonStyle(.sumiButton(role: .destructive))

            Button("Erase Everything", systemImage: "flame") {
                RuntimeDiagnostics.emit("Erase")
            }
            .buttonStyle(.sumiButtonProminent(role: .destructive))

            Button("Disabled") {
                RuntimeDiagnostics.emit("Disabled")
            }
            .buttonStyle(.sumiButtonProminent)
            .disabled(true)
        }
    }
}
