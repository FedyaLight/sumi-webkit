//
//  ProfilePickerView.swift
//  Sumi
//
//  Reusable picker for selecting a profile in menus and settings.
//

import SwiftUI

struct ProfilePickerView: View {
    @EnvironmentObject var browserManager: BrowserManager

    // Binding to the selected profile id (must always have a profile)
    @Binding var selectedProfileId: UUID

    // Optional callback when a selection is made
    var onSelect: ((UUID) -> Void)? = nil

    // Visual style variants
    var compact: Bool = true

    var body: some View {
        let profiles = browserManager.profileManager.profiles

        if profiles.isEmpty {
            EmptyProfilesView()
        } else if compact {
            CompactListView(
                profiles: profiles,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        } else {
            FullListView(
                profiles: profiles,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        }
    }

    // Compact vertical list – suitable for menus/context menus
    private struct CompactListView: View {
        let profiles: [Profile]
        @Binding var selectedProfileId: UUID
        var onSelect: ((UUID) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: 8) {
                            SumiProfileGlyphDisplay(icon: p.icon, font: .system(size: 13))
                            Text(p.name).font(.system(size: 13))
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private func select(_ id: UUID) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    // Full list with dividers and clearer spacing – for settings
    private struct FullListView: View {
        let profiles: [Profile]
        @Binding var selectedProfileId: UUID
        var onSelect: ((UUID) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.controlBackgroundColor))
                                SumiProfileGlyphDisplay(icon: p.icon, font: .system(size: 16))
                            }
                            .frame(width: 24, height: 24)
                            Text(p.name).lineLimit(1)
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private func select(_ id: UUID) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    private struct EmptyProfilesView: View {
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text("No profiles available")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityLabel("No profiles available")
        }
    }
}
