//
//  SettingsComponents.swift
//  Sumi
//

import AppKit
import SwiftUI

private enum SettingsLayout {
    static let sectionCornerRadius: CGFloat = 14
    static let rowControlWidth: CGFloat = 220
}

enum SettingsSurfaceStyle {
    static let groupedCornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 8

    static var pageBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var groupedBackground: Color {
        Color.primary.opacity(0.055)
    }

    static var groupedBackgroundProminent: Color {
        Color.primary.opacity(0.075)
    }

    static var fieldBackground: Color {
        Color.primary.opacity(0.055)
    }

    static var separator: Color {
        Color.primary.opacity(0.08)
    }

    static var stroke: Color {
        Color.primary.opacity(0.06)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayout.sectionCornerRadius, style: .continuous)
                .fill(SettingsSurfaceStyle.groupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.sectionCornerRadius, style: .continuous)
                .strokeBorder(SettingsSurfaceStyle.stroke, lineWidth: 1)
        )
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var control: Control

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)
                control
                    .controlSize(.regular)
            }
            .frame(width: SettingsLayout.rowControlWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct SettingsActionRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let buttonTitle: String
    var role: ButtonRole? = nil
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

struct SettingsEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
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
struct SettingsSectionFooter: View {
    var buttonTitle: String = "Restore Defaults"
    var infoText: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SettingsDivider()

            HStack(spacing: 10) {
                if let infoText {
                    Text(infoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}


extension View {
    func settingsTrailingControl(width: CGFloat) -> some View {
        fixedSize(horizontal: true, vertical: false)
            .frame(width: width, alignment: .trailing)
    }
}
