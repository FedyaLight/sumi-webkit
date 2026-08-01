//
//  SettingsComponents.swift
//  Sumi
//

import AppKit
import SwiftUI

private enum SettingsLayout {
    static let sectionCornerRadius: CGFloat = 11
    static let rowControlWidth: CGFloat = 220
}

enum SettingsSurfaceStyle {
    static let groupedCornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 8

    static var groupedBackground: Color {
        SettingsThemeTokens.Colors.groupedBackground
    }

    static var fieldBackground: Color {
        SettingsThemeTokens.Colors.fieldBackground
    }

    static var separator: Color {
        SettingsThemeTokens.Colors.separator
    }

    static var stroke: Color {
        SettingsThemeTokens.Colors.stroke
    }

    static var selectedNavigationBackground: Color {
        SettingsThemeTokens.Colors.selectedNavigationBackground
    }

    static var selectedNavigationForeground: Color {
        SettingsThemeTokens.Colors.selectedNavigationForeground
    }

    static var compactSelectedNavigationBackground: Color {
        SettingsThemeTokens.Colors.compactSelectedNavigationBackground
    }

    static var paneIconForeground: Color {
        SettingsThemeTokens.Colors.paneIconForeground
    }

    static var paneIconShadow: Color {
        SettingsThemeTokens.Colors.paneIconShadow
    }

    static var floatingRowShadow: Color {
        SettingsThemeTokens.Colors.floatingRowShadow
    }

    static var warningText: Color {
        SettingsThemeTokens.Colors.warningText
    }

    static var warningBackground: Color {
        SettingsThemeTokens.Colors.warningBackground
    }

    static var warningBorder: Color {
        SettingsThemeTokens.Colors.warningBorder
    }
}

typealias SettingsTypography = SettingsThemeTokens.Typography

struct SettingsSection<Content: View>: View {
    let title: String?
    var subtitle: String?
    var headerAccessory: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerAccessory = nil
        self.content = content()
    }

    init<HeaderAccessory: View>(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerAccessory = AnyView(headerAccessory())
        self.content = content()
    }

    var body: some View {
        if content is EmptyView {
            summaryCard
        } else {
            groupedContent
        }
    }

    private var groupedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasHeader {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let headerAccessory {
                        headerAccessory
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(sectionBackground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let headerAccessory {
                headerAccessory
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(sectionBackground)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: SettingsLayout.sectionCornerRadius, style: .continuous)
            .fill(SettingsSurfaceStyle.groupedBackground)
    }

    private var hasHeader: Bool {
        title != nil || subtitle != nil || headerAccessory != nil
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var verticalPadding: CGFloat
    @ViewBuilder var control: Control

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        verticalPadding: CGFloat = 10,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.verticalPadding = verticalPadding
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                control
                    .controlSize(.small)
            }
            .frame(width: SettingsLayout.rowControlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
    }
}

struct SettingsActionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let buttonTitle: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            Button(buttonTitle, role: role, action: action)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(SettingsSurfaceStyle.separator)
    }
}

struct SettingsDeleteButton: View {
    let label: LocalizedStringResource
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(SettingsTypography.searchEngineActionIcon)
        }
        .buttonStyle(NavButtonStyle(size: .small))
        .disabled(isDisabled)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

struct SettingsEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(SettingsTypography.emptyStateIcon)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}
struct SettingsPillBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(SettingsSurfaceStyle.fieldBackground)
            )
    }
}

extension View {
    func settingsTrailingControl(width: CGFloat) -> some View {
        fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .trailing)
    }

    func settingsMenuPicker(width: CGFloat) -> some View {
        labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .trailing)
    }
}
