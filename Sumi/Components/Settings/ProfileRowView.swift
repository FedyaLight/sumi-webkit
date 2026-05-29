//
//  ProfileRowView.swift
//  Sumi
//
//  Row used in Profiles settings list.
//

import SwiftUI

struct ProfileRowView: View {
    let profile: Profile
    let isSelected: Bool
    let spacesCount: Int
    let tabsCount: Int
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                SumiProfileIconView(
                    icon: profile.icon,
                    font: .system(size: 20, weight: .medium)
                )
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

            Button(action: onEdit) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
            }
            .buttonStyle(.borderless)
            .help("Edit Profile")
            .accessibilityLabel("Edit \(profile.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
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
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if isHovering {
            return Color.primary.opacity(0.04)
        }
        return .clear
    }

    private var profileDetailText: String {
        let spaces = spacesCount == 1 ? "1 space" : "\(spacesCount) spaces"
        let tabs = tabsCount == 1 ? "1 tab" : "\(tabsCount) tabs"
        return "\(spaces) - \(tabs)"
    }
}
