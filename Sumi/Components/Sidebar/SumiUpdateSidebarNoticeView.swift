//
//  SumiUpdateSidebarNoticeView.swift
//  Sumi
//

import SwiftUI

struct SumiUpdateSidebarNoticeView: View {
    private static let hoverExpandAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.86
    )

    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @Environment(\.chromeThemeTokens) private var chromeTokens
    @State private var isHovered = false

    private var isExpanded: Bool {
        isHovered || notice.showsPersistentStatus
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        VStack(spacing: 0) {
            Text(notice.title)
                .font(SumiUpdateSidebarNoticeThemeTokens.Typography.availableTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            SumiUpdateSidebarActionButton(
                title: notice.sidebarActionTitle,
                accessibilityLabel: notice.sidebarActionAccessibilityLabel,
                isEnabled: notice.primaryActionTitle != nil || notice.isDismissible,
                isVisible: isExpanded,
                action: handleAction
            )
            .padding(.top, 7)
            .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(isExpanded)
        }
        .padding(.horizontal, isExpanded ? 8 : 10)
        .padding(.vertical, isExpanded ? 8 : 4)
        .frame(maxWidth: .infinity)
        .background {
            shape.fill(
                isExpanded
                    ? SumiUpdateSidebarNoticeThemeTokens.Colors.availableCardBackground(
                        tokens: chromeTokens
                    )
                    : SumiUpdateSidebarNoticeThemeTokens.Colors.availablePillBackground(
                        tokens: chromeTokens
                    )
            )
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isExpanded
                    ? SumiUpdateSidebarNoticeThemeTokens.Colors.availableCardBorder(
                        tokens: chromeTokens
                    )
                    : SumiUpdateSidebarNoticeThemeTokens.Colors.availablePillBorder(
                        tokens: chromeTokens
                    ),
                lineWidth: 0.75
            )
        }
        .shadow(
            color: .black.opacity(isExpanded ? 0.08 : 0),
            radius: isExpanded ? 7 : 0,
            x: 0,
            y: isExpanded ? 2 : 0
        )
        .contentShape(Rectangle())
        .sidebarHover { hovering in
            withAnimation(Self.hoverExpandAnimation) {
                isHovered = hovering
            }
        }
        .animation(Self.hoverExpandAnimation, value: notice.showsPersistentStatus)
        .accessibilityElement(children: .contain)
    }

    private func handleAction() {
        if notice.primaryActionTitle != nil {
            onUpdate()
        } else if notice.isDismissible {
            onDismiss()
        }
    }
}

private struct SumiUpdateSidebarActionButton: View {
    let title: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let isVisible: Bool
    let action: () -> Void

    @Environment(\.chromeThemeTokens) private var chromeTokens

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SumiUpdateSidebarNoticeThemeTokens.Typography.availableAction)
                .foregroundStyle(
                    SumiUpdateSidebarNoticeThemeTokens.Colors.availableActionForeground(
                        tokens: chromeTokens
                    )
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            SumiUpdateSidebarNoticeThemeTokens.Colors.availableActionBackground(
                                tokens: chromeTokens
                            )
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SumiUpdateSidebarCompactIndicator: View {
    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            Image(systemName: notice.systemImageName)
                .font(SumiUpdateSidebarNoticeThemeTokens.Typography.compactIcon)
                .symbolRenderingMode(.monochrome)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(symbolColor)
        .background(
            Circle()
                .fill(symbolColor.opacity(0.18))
        )
        .overlay(
            Circle()
                .strokeBorder(symbolColor.opacity(0.26), lineWidth: 1)
        )
        .contentShape(Circle())
        .help(notice.title)
        .accessibilityLabel("\(notice.title), \(notice.detail)")
    }

    private var symbolColor: Color {
        SumiUpdateSidebarNoticeThemeTokens.Colors.symbol(for: notice.visualStyle)
    }
}
