//
//  SumiUpdateSidebarNoticeView.swift
//  Sumi
//

import Foundation
import SwiftUI

struct SumiUpdateSidebarNoticeView: View {
    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void
    let onDismiss: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        switch notice {
        case .installed(let update):
            SumiUpdateSidebarInstalledNoticeView(
                update: update,
                onDismiss: onDismiss,
                onOpenURL: onOpenURL
            )
        case .progress(let progressNotice):
            SumiUpdateSidebarProgressNoticeView(
                notice: progressNotice,
                onUpdate: onUpdate,
                onDismiss: onDismiss
            )
        }
    }
}

private struct SumiUpdateSidebarProgressNoticeView: View {
    private static let hoverExpandAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.86
    )

    let notice: SumiUpdateSidebarProgressNotice
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

private struct SumiUpdateSidebarInstalledNoticeView: View {
    let update: SumiInstalledUpdate
    let onDismiss: () -> Void
    let onOpenURL: (URL) -> Void

    @Environment(\.chromeThemeTokens) private var chromeTokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        VStack(spacing: 0) {
            SumiUpdateSidebarInstalledNoticeHeader(onDismiss: onDismiss)

            VStack(spacing: 2) {
                SumiUpdateSidebarLinkRow(
                    title: "What's new in Sumi",
                    systemImageName: "heart.circle.fill",
                    url: SumiUpdateReleaseNotesURL.url(
                        forDisplayVersion: update.displayVersion
                    ),
                    foreground: SumiUpdateSidebarNoticeThemeTokens.Colors.completedAccent,
                    onOpenURL: openLink
                )

                SumiUpdateSidebarLinkRow(
                    title: "Support us",
                    systemImageName: "gift",
                    url: SumiExternalLinks.support,
                    foreground: SumiUpdateSidebarNoticeThemeTokens.Colors.completedNeutralForeground(
                        tokens: chromeTokens
                    ),
                    onOpenURL: openLink
                )

                SumiUpdateSidebarLinkRow(
                    title: "Something broke?",
                    systemImageName: "exclamationmark.bubble",
                    url: SumiExternalLinks.issues,
                    foreground: SumiUpdateSidebarNoticeThemeTokens.Colors.completedNeutralForeground(
                        tokens: chromeTokens
                    ),
                    onOpenURL: openLink
                )
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(
            SumiUpdateSidebarNoticeThemeTokens.Colors.completedCardBackground(
                tokens: chromeTokens
            )
        ))
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                SumiUpdateSidebarNoticeThemeTokens.Colors.completedCardBorder(
                    tokens: chromeTokens
                ),
                lineWidth: 0.75
            )
        }
        .shadow(color: .black.opacity(0.08), radius: 7, x: 0, y: 2)
        .accessibilityElement(children: .contain)
    }

    private func openLink(_ url: URL) {
        onOpenURL(url)
        onDismiss()
    }
}

private struct SumiUpdateSidebarInstalledNoticeHeader: View {
    let onDismiss: () -> Void

    @Environment(\.chromeThemeTokens) private var chromeTokens
    @State private var isCloseHovered = false

    var body: some View {
        ZStack {
            Text("Update Complete!")
                .font(SumiUpdateSidebarNoticeThemeTokens.Typography.completedHeading)
                .foregroundStyle(
                    SumiUpdateSidebarNoticeThemeTokens.Colors.completedHeadingForeground(
                        tokens: chromeTokens
                    )
                )
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .overlay(alignment: .trailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(SidebarThemeTokens.Typography.essentialsPlaceholderDismiss)
                    .foregroundStyle(
                        SumiUpdateSidebarNoticeThemeTokens.Colors.completedCloseForeground(
                            tokens: chromeTokens
                        )
                    )
                    .frame(
                        width: EssentialsPlaceholderMetrics.dismissHitSize,
                        height: EssentialsPlaceholderMetrics.dismissHitSize
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                isCloseHovered
                                    ? SumiUpdateSidebarNoticeThemeTokens.Colors.completedRowHover(
                                        tokens: chromeTokens
                                    )
                                    : .clear
                            )
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(EssentialsPlaceholderMetrics.dismissInset)
            .sidebarHover { hovering in
                isCloseHovered = hovering
            }
            .accessibilityLabel("Dismiss update complete notice")
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    SumiUpdateSidebarNoticeThemeTokens.Colors.completedSeparator(
                        tokens: chromeTokens
                    )
                )
                .frame(height: 0.75)
        }
    }
}

private struct SumiUpdateSidebarLinkRow: View {
    let title: LocalizedStringResource
    let systemImageName: String
    let url: URL
    let foreground: Color
    let onOpenURL: (URL) -> Void

    @Environment(\.chromeThemeTokens) private var chromeTokens
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpenURL(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImageName)
                    .font(SumiUpdateSidebarNoticeThemeTokens.Typography.completedIcon)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(SumiUpdateSidebarNoticeThemeTokens.Typography.completedLink)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isHovered
                            ? SumiUpdateSidebarNoticeThemeTokens.Colors.completedRowHover(
                                tokens: chromeTokens
                            )
                            : .clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .sidebarHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(Text(title))
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
