//
//  NavMenuStyle.swift
//  Sumi
//
//  Created by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct NavMenuStyle: MenuStyle {
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuIndicator(.hidden)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                    .frame(width: size, height: size)
            }
            .opacity(isEnabled ? 1.0 : 0.3)
            .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
            .scaleEffect(isPressed && isEnabled ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }

    private var size: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }

    private var cornerRadius: CGFloat {
        8
    }

    private var backgroundColor: Color {
        guard (isHovering || isPressed) && isEnabled else {
            return .clear
        }

        let tokens = themeContext.tokens(settings: sumiSettings)
        return isPressed ? tokens.chromeControlPressedBackground : tokens.chromeControlHoverBackground
    }
}

#Preview {
    VStack(spacing: 20) {
        // Default
        Menu("Options", systemImage: "ellipsis") {
            Button("Item 1") { }
            Button("Item 2") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())

        // With foregroundStyle
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Option A") { }
            Button("Option B") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())
        .foregroundStyle(.red)

        // Different sizes
        HStack {
            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.mini)

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.small)

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.large)
        }

        // Disabled
        Menu("Disabled", systemImage: "gear") {
            Button("Item") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())
        .disabled(true)
    }
    .padding()
}
