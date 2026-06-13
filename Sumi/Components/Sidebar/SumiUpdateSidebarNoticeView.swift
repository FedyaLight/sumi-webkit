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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(notice.detail)
                        .font(.system(size: 12))
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
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.94 : 0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.18 : 0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.10 : 0.06), radius: 8, x: 0, y: 2)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title), \(notice.detail)")
    }

    private var symbolColor: Color {
        switch notice.visualStyle {
        case .accent, .progress:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .yellow
        }
    }
}

private struct SumiUpdateSidebarStatusIcon: View {
    let notice: SumiUpdateSidebarNotice

    var body: some View {
        Image(systemName: notice.systemImageName)
            .font(.system(size: 15, weight: .semibold))
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
        switch notice.visualStyle {
        case .accent, .progress:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .yellow
        }
    }
}

private struct SumiUpdateSidebarDismissButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(isHovering ? 0.86 : 0.68))
        .background(
            Circle()
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0.075))
        )
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.10), lineWidth: 1)
            .frame(width: 24, height: 24)
        )
        .help("Dismiss update notice")
        .accessibilityLabel("Dismiss update notice")
        .onHover { isHovering = $0 }
    }
}

struct SumiUpdateSidebarCompactIndicator: View {
    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void

    var body: some View {
        Button(action: onUpdate) {
            Image(systemName: notice.systemImageName)
                .font(.system(size: 17, weight: .semibold))
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
        switch notice.visualStyle {
        case .accent, .progress:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .yellow
        }
    }
}
