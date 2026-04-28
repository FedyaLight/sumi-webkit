import SwiftUI

struct SumiSiteSettingsNavigationRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct SumiSiteSettingsPermissionControlRow: View {
    let row: SumiSiteSettingsPermissionRow
    let onSelect: (SumiCurrentSitePermissionOption) -> Void
    var onOpenSystemSettings: (() -> Void)?

    var body: some View {
        SettingsRow(title: row.title, subtitle: row.statusLines.joined(separator: "\n"), systemImage: row.systemImage) {
            HStack(spacing: 8) {
                if row.showsSystemSettingsAction, let onOpenSystemSettings {
                    Button {
                        onOpenSystemSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open System Settings")
                    .accessibilityLabel("Open System Settings for \(row.title)")
                }

                if row.isEditable, let currentOption = row.currentOption, !row.availableOptions.isEmpty {
                    Menu(currentOption.shortTitle) {
                        ForEach(row.availableOptions) { option in
                            Button(option.title) {
                                onSelect(option)
                            }
                        }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .accessibilityLabel("\(row.title), current setting \(currentOption.title)")
                } else if let currentOption = row.currentOption {
                    Text(currentOption.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel(row.accessibilityLabel)
    }
}

struct SumiSiteSettingsStatusMessage: View {
    let message: String?
    var isError = false

    var body: some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(.caption)
                .foregroundStyle(isError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SumiSiteSettingsSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }
}
