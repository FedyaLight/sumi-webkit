//
//  SumiUpdateSidebarNoticeView.swift
//  Sumi
//

import SwiftUI

struct SumiUpdateSidebarNoticeView: View {
    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    private let cardCornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                SumiUpdateSidebarStatusIcon(notice: notice)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(SumiUpdateSidebarNoticeThemeTokens.Typography.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(notice.detail)
                        .font(SumiUpdateSidebarNoticeThemeTokens.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if notice.isDismissible {
                    SumiUpdateSidebarDismissButton(action: onDismiss)
                }
            }

            if let primaryActionTitle = notice.primaryActionTitle {
                HStack {
                    Spacer(minLength: 0)

                    Button(primaryActionTitle, action: onUpdate)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Update Sumi")

                    Spacer(minLength: 0)
                }
            } else if let progress = notice.progress {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .tint(symbolColor)
            } else if case .operation = notice {
                ProgressView()
                    .controlSize(.small)
                    .tint(symbolColor)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(SumiUpdateSidebarNoticeThemeTokens.Colors.cardBackground(isHovering: isHovering))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    SumiUpdateSidebarNoticeThemeTokens.Colors.cardBorder(isHovering: isHovering),
                    lineWidth: 1
                )
        )
        .shadow(
            color: SumiUpdateSidebarNoticeThemeTokens.Colors.cardShadow(isHovering: isHovering),
            radius: 8,
            x: 0,
            y: 2
        )
        .sidebarHover($isHovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title), \(notice.detail)")
    }

    private var symbolColor: Color {
        SumiUpdateSidebarNoticeThemeTokens.Colors.symbol(for: notice.visualStyle)
    }
}

private struct SumiUpdateSidebarStatusIcon: View {
    let notice: SumiUpdateSidebarNotice

    var body: some View {
        Image(systemName: notice.systemImageName)
            .font(SumiUpdateSidebarNoticeThemeTokens.Typography.statusIcon)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(symbolColor)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(symbolColor.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(symbolColor.opacity(0.24), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var symbolColor: Color {
        SumiUpdateSidebarNoticeThemeTokens.Colors.symbol(for: notice.visualStyle)
    }
}

private struct SumiUpdateSidebarDismissButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(SumiUpdateSidebarNoticeThemeTokens.Typography.dismissIcon)
                .symbolRenderingMode(.monochrome)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(SumiUpdateSidebarNoticeThemeTokens.Colors.dismissForeground(isHovering: isHovering))
        .background(
            Circle()
                .fill(SumiUpdateSidebarNoticeThemeTokens.Colors.dismissBackground(isHovering: isHovering))
        )
        .overlay(
            Circle()
                .strokeBorder(
                    SumiUpdateSidebarNoticeThemeTokens.Colors.dismissBorder(isHovering: isHovering),
                    lineWidth: 1
                )
            .frame(width: 24, height: 24)
        )
        .help("Dismiss update notice")
        .accessibilityLabel("Dismiss update notice")
        .sidebarHover($isHovering)
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
