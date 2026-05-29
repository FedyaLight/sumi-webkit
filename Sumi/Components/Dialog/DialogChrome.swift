import SwiftUI

struct DialogCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: 500, alignment: .leading)
            .floatingChromeSurface(
                .panel,
                opacity: 0.97,
                cornerRadius: 12,
                drawsBorder: true,
                drawsShadow: true
            )
    }
}

struct StandardDialog<Header: View, Content: View, Footer: View>: View {
    private let header: AnyView?
    private let content: Content
    private let footer: AnyView?

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        let headerView = header()
        self.header = Header.self == EmptyView.self ? nil : AnyView(headerView)
        self.content = content()
        let footerView = footer()
        self.footer = Footer.self == EmptyView.self ? nil : AnyView(footerView)
    }

    var body: some View {
        DialogCard {
            VStack(alignment: .leading, spacing: 25) {
                if let header {
                    header
                }

                content

                if let footer {
                    VStack(alignment: .leading, spacing: 15) {
                        footer
                    }
                }
            }
        }
    }
}

struct DialogHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        let accent = Color(nsColor: .controlAccentColor)
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.top, 8)
    }
}

struct DialogFooter: View {
    let leftButton: DialogButton?
    let rightButtons: [DialogButton]

    init(leftButton: DialogButton? = nil, rightButtons: [DialogButton]) {
        self.leftButton = leftButton
        self.rightButtons = rightButtons
    }

    var body: some View {
        HStack {
            if let leftButton {
                dialogButton(leftButton)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(Array(rightButtons.indices), id: \.self) { index in
                    dialogButton(rightButtons[index])
                }
            }
        }
    }

    private func dialogButton(_ button: DialogButton) -> some View {
        Button(button.text, action: button.action)
            .buttonStyle(
                DialogButtonStyle(
                    variant: button.variant,
                    icon: button.iconName.map {
                        AnyView(Image(systemName: $0))
                    },
                    iconPosition: .trailing
                )
            )
            .controlSize(.extraLarge)
            .disabled(!button.isEnabled)
            .modifier(
                OptionalKeyboardShortcut(
                    shortcut: button.keyboardShortcut
                )
            )
    }
}

struct DialogButton {
    let text: String
    let iconName: String?
    let variant: DialogButtonStyleVariant
    let action: () -> Void
    let keyboardShortcut: KeyEquivalent?
    let isEnabled: Bool

    init(
        text: String,
        iconName: String? = nil,
        variant: DialogButtonStyleVariant = .secondary,
        keyboardShortcut: KeyEquivalent? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
        self.keyboardShortcut = keyboardShortcut
        self.isEnabled = isEnabled
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyEquivalent?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut, modifiers: [])
        } else {
            content
        }
    }
}

enum DialogButtonStyleVariant {
    case primary
    case secondary
    case danger
}

struct DialogButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    var variant: DialogButtonStyleVariant = .primary
    var icon: AnyView?
    var iconPosition: IconPosition = .trailing

    enum IconPosition {
        case leading, trailing
    }

    private let padding = EdgeInsets(
        top: 10,
        leading: 16,
        bottom: 10,
        trailing: 16
    )
    private let cornerRadius: CGFloat = 10

    private var backgroundColor: Color {
        switch variant {
        case .primary: return tokens.buttonPrimaryBackground
        case .secondary: return tokens.buttonSecondaryBackground
        case .danger: return Color(hex: "F60000")
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .black
        case .secondary: return tokens.primaryText
        case .danger: return .white
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if iconPosition == .leading, let icon {
                icon
            }

            configuration.label
                .font(.system(size: 13, weight: .medium))

            if iconPosition == .trailing, let icon {
                icon
            }
        }
        .padding(padding)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
