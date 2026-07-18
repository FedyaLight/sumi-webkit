//
//  ProfileRowView.swift
//  Sumi
//
//  Row used in Profiles settings list.
//

import SwiftUI

struct ProfileRowView: View {
    let profile: Profile
    let spacesCount: Int
    let tabsCount: Int
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(profileDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(SettingsThemeTokens.Typography.profileRowActionIcon)
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .help("Edit Profile")
                .accessibilityLabel("Edit \(profile.name)")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(SettingsThemeTokens.Typography.profileRowActionIcon)
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .disabled(!canDelete)
                .help("Delete Profile")
                .accessibilityLabel("Delete \(profile.name)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Profile...") {
                onEdit()
            }

            Divider()

            Button("Delete Profile...", role: .destructive) {
                onDelete()
            }
            .disabled(!canDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profileDetailText)")
    }

    private var profileDetailText: String {
        let spaces = spacesCount == 1 ? "1 space" : "\(spacesCount) spaces"
        let tabs = tabsCount == 1 ? "1 tab" : "\(tabsCount) tabs"
        return "\(spaces) - \(tabs)"
    }
}
