//
//  DialogManager.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
class DialogManager {
    var isVisible: Bool = false
    var activeDialog: AnyView?
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared
    @ObservationIgnored private weak var presentedWindow: NSWindow?
    @ObservationIgnored private var presentedSource: SidebarTransientPresentationSource?
    @ObservationIgnored private var presentedSessionToken: SidebarTransientSessionToken?
    @ObservationIgnored var presentationWindowResolver: @MainActor () -> NSWindow? = {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    /// Invoked at the start of every modal dialog presentation (e.g. to tear down lower-priority transients such as the workspace theme picker).
    @ObservationIgnored var onWillPresentModal: (@MainActor () -> Void)?

    // MARK: - Presentation

    func showDialog<Content: View>(
        _ dialog: Content,
        in window: NSWindow? = nil,
        source: SidebarTransientPresentationSource? = nil
    ) {
        onWillPresentModal?()
        endPresentedSessionIfNeeded()
        let resolvedWindow = source?.window ?? window ?? presentationWindowResolver()
        presentedWindow = resolvedWindow
        presentedSource = source
        presentedSessionToken = source.flatMap {
            $0.coordinator?.beginSession(
                kind: .dialog,
                source: $0,
                path: "DialogManager.showDialog"
            )
        }
        activeDialog = AnyView(dialog)
        isVisible = true
    }

    func showDialog<Content: View>(
        @ViewBuilder builder: () -> Content,
        in window: NSWindow? = nil,
        source: SidebarTransientPresentationSource? = nil
    ) {
        showDialog(builder(), in: window, source: source)
    }

    func isPresented(in window: NSWindow?) -> Bool {
        guard isVisible, activeDialog != nil else { return false }
        guard let presentedWindow else { return true }
        return presentedWindow === window
    }

    func closeDialog() {
        guard isVisible else {
            activeDialog = nil
            presentedWindow = nil
            endPresentedSessionIfNeeded()
            return
        }

        let recoveryWindow = presentedWindow ?? presentationWindowResolver()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isVisible = false
            activeDialog = nil
        }

        presentedWindow = nil
        if let presentedSessionToken,
           let coordinator = presentedSource?.coordinator
        {
            coordinator.finishSession(
                presentedSessionToken,
                reason: "DialogManager.closeDialog"
            )
        } else {
            sidebarRecoveryCoordinator.recover(in: recoveryWindow)
        }
        presentedSource = nil
        presentedSessionToken = nil
    }

    private func endPresentedSessionIfNeeded() {
        guard let presentedSessionToken,
              let coordinator = presentedSource?.coordinator
        else {
            presentedSessionToken = nil
            presentedSource = nil
            return
        }

        coordinator.finishSession(
            presentedSessionToken,
            reason: "DialogManager.endPresentedSessionIfNeeded"
        )
        self.presentedSessionToken = nil
        self.presentedSource = nil
    }
}

protocol DialogPresentable: View {
    associatedtype DialogContent: View

    @ViewBuilder func dialogHeader() -> DialogHeader
    @ViewBuilder func dialogContent() -> DialogContent
    @ViewBuilder func dialogFooter() -> DialogFooter
    @ViewBuilder func dialogChrome(
        header: DialogHeader,
        content: DialogContent,
        footer: DialogFooter
    ) -> AnyView
}

extension DialogPresentable {
    @ViewBuilder
    func dialogChrome(
        header: DialogHeader,
        content: DialogContent,
        footer: DialogFooter
    ) -> AnyView {
        AnyView(
            StandardDialog(
                header: { header },
                content: { content },
                footer: { footer }
            )
        )
    }

    var body: some View {
        let header = dialogHeader()
        let content = dialogContent()
        let footer = dialogFooter()
        return dialogChrome(header: header, content: content, footer: footer)
    }
}

// MARK: - Dialog Surfaces

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
                        //                        Divider()
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
                    .foregroundStyle(accent).frame(
                        width: 48,
                        height: 48
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
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
            if let leftButton = leftButton {
                if leftButton.iconName != nil {
                    Button(leftButton.text, action: leftButton.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: leftButton.variant,
                                icon: leftButton.iconName.map {
                                    AnyView(Image(systemName: $0))
                                },
                                iconPosition: .trailing
                            )
                        )
                        .controlSize(.extraLarge)

                        .disabled(!leftButton.isEnabled)
                        .modifier(
                            OptionalKeyboardShortcut(
                                shortcut: leftButton.keyboardShortcut
                            )
                        )
                } else {
                    Button(leftButton.text, action: leftButton.action)
                        .buttonStyle(
                            DialogButtonStyle(
                                variant: leftButton.variant,
                                icon: leftButton.iconName.map {
                                    AnyView(Image(systemName: $0))
                                },
                                iconPosition: .trailing
                            )
                        )
                        .controlSize(.extraLarge)
                        .disabled(!leftButton.isEnabled)
                        .modifier(
                            OptionalKeyboardShortcut(
                                shortcut: leftButton.keyboardShortcut
                            )
                        )
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(Array(rightButtons.indices), id: \.self) { index in
                    let button = rightButtons[index]

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
        }
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
        if let shortcut = shortcut {
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
            if iconPosition == .leading, let icon = icon {
                icon
            }

            configuration.label
                .font(.system(size: 13, weight: .medium))

            if iconPosition == .trailing, let icon = icon {
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
