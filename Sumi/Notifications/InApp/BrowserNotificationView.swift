//
//  BrowserNotificationView.swift
//  Sumi
//
//  In-app notification chrome and stack presentation.
//

import SwiftUI

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

private struct BrowserNotificationChrome<Content: View>: View {
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

struct BrowserNotificationView: View {
    let notification: BrowserNotification
    let pulseToken: Int
    let reduceMotion: Bool
    let onDismiss: () -> Void
    let onPauseTimer: () -> Void
    let onResumeTimer: () -> Void
    let onRestartTimer: () -> Void

    @State private var isPulsing = false

    var body: some View {
        BrowserNotificationChrome {
            HStack(spacing: 10) {
                if let icon = notification.icon {
                    Image(systemName: icon)
                        .font(BrowserNotificationThemeTokens.Typography.leadingIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(BrowserNotificationThemeTokens.Typography.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = notification.subtitle {
                        Text(subtitle)
                            .font(BrowserNotificationThemeTokens.Typography.subtitle)
                            .foregroundStyle(.primary.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

                if let controls = notification.controls, !controls.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(controls) { control in
                            BrowserNotificationControlButton(
                                control: control,
                                onActivate: {
                                    control.handler()
                                    if control.dismissesOnActivate {
                                        onDismiss()
                                    } else {
                                        onRestartTimer()
                                    }
                                }
                            )
                        }
                    }
                } else if let action = notification.action {
                    Button(action.label) {
                        action.handler()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .buttonBorderShape(.roundedRectangle(radius: 6))
                }
            }
        }
        .scaleEffect(isPulsing ? 1.02 : 1, anchor: .topTrailing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: isPulsing)
        .onHover { isHovering in
            if isHovering {
                onPauseTimer()
            } else {
                onResumeTimer()
            }
        }
        .onChange(of: pulseToken) { _, _ in
            guard !reduceMotion else { return }
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPulsing = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        if notification.controls != nil {
            return "Double tap to dismiss. Zoom controls available."
        }
        return notification.action == nil
            ? "Double tap to dismiss."
            : "Double tap to dismiss. Undo action available."
    }

    private var accessibilityLabel: String {
        if let subtitle = notification.subtitle {
            return "\(notification.title). \(subtitle)"
        }
        return notification.title
    }
}

private struct BrowserNotificationControlButton: View {
    let control: BrowserNotificationControl
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            controlLabel
        }
        .buttonStyle(BrowserNotificationControlButtonStyle(isTextControl: isTextControl))
        .disabled(control.isDisabled)
        .accessibilityLabel(control.accessibilityLabel)
    }

    private var isTextControl: Bool {
        if case .text = control.kind {
            return true
        }
        return false
    }

    @ViewBuilder
    private var controlLabel: some View {
        switch control.kind {
        case let .systemImage(name):
            Image(systemName: name)
                .font(BrowserNotificationThemeTokens.Typography.actionIcon)
        case let .text(label):
            Text(label)
                .font(BrowserNotificationThemeTokens.Typography.actionLabel)
        }
    }
}

private struct BrowserNotificationControlButtonStyle: ButtonStyle {
    let isTextControl: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, isTextControl ? 8 : 0)
            .frame(minWidth: isTextControl ? 44 : 24, minHeight: 24)
            .frame(width: isTextControl ? nil : 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let ramp = BrowserNotificationThemeTokens.Colors.ActionBackground.self
        if isPressed {
            return ramp.pressed
        }
        if isHovering {
            return ramp.hovered
        }
        return ramp.rest
    }
}

struct BrowserNotificationStackView: View {
    let center: BrowserNotificationCenter
    let animation: Animation
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.items) { item in
                BrowserNotificationView(
                    notification: item.notification,
                    pulseToken: item.pulseToken,
                    reduceMotion: reduceMotion,
                    onDismiss: {
                        center.dismiss(id: item.id)
                    },
                    onPauseTimer: {
                        center.pauseTimer(id: item.id)
                    },
                    onResumeTimer: {
                        center.resumeTimer(id: item.id)
                    },
                    onRestartTimer: {
                        center.restartTimer(id: item.id)
                    }
                )
                .transition(reduceMotion ? .opacity : .toast)
            }
        }
        .animation(animation, value: center.items.map(\.id))
    }
}
