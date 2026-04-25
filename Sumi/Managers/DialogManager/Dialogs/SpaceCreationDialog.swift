//
//  SpaceCreationDialog.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI

struct SpaceCreationDialog: DialogPresentable {
    @State private var spaceName: String
    @State private var spaceIcon: String
    @State private var selectedProfileId: UUID?

    let onCreate: (String, String, UUID?) -> Void
    let onCancel: () -> Void

    init(
        onCreate: @escaping (String, String, UUID?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _spaceName = State(initialValue: "")
        _spaceIcon = State(initialValue: "")
        _selectedProfileId = State(initialValue: nil)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "folder.badge.plus",
            title: "Create a New Space",
            subtitle: "Organize your tabs into a new space"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        SpaceCreationContent(
            spaceName: $spaceName,
            spaceIcon: $spaceIcon,
            selectedProfileId: $selectedProfileId
        )
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Create Space",
                    iconName: "plus",
                    variant: .primary,
                    keyboardShortcut: .return,
                    action: handleCreate
                )
            ]
        )
    }

    private func handleCreate() {
        let trimmedName = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedName, spaceIcon, selectedProfileId)
    }
}

struct SpaceCreationContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    @Binding var selectedProfileId: UUID?
    @StateObject private var emojiManager = EmojiPickerManager()
    @State private var isProfileCreationPresented = false
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Space Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                SumiTextField(
                    text: $spaceName,
                    placeholder: "Enter space name",
                    variant: .default,
                    iconName: "textformat"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Space Icon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Button {
                        emojiManager.toggle(
                            settings: sumiSettings,
                            themeContext: themeContext
                        )
                    } label: {
                        Text(
                            emojiManager.selectedEmoji.isEmpty
                                ? "✨" : emojiManager.selectedEmoji
                        )
                        .font(.system(size: 14))
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .buttonStyle(PlainButtonStyle())

                    Text("Choose an emoji to represent this space")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 12) {
                    Picker(
                        currentProfileName,
                        systemImage: currentProfilePickerSymbolName,
                        selection: Binding(
                            get: {
                                selectedProfileId ?? browserManager.profileManager.profiles.first?.id ?? UUID()
                            },
                            set: { newId in
                                selectedProfileId = newId
                            }
                        )
                    ) {
                        ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                            SumiProfileMenuLabel(name: profile.name, icon: profile.icon).tag(profile.id)
                        }
                    }

                    Button {
                        isProfileCreationPresented = true
                    } label: {
                        Label("Create New Profile", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            if !spaceIcon.isEmpty {
                emojiManager.selectedEmoji = spaceIcon
            }
            if selectedProfileId == nil {
                selectedProfileId = browserManager.currentProfile?.id
                    ?? browserManager.profileManager.profiles.first?.id
            }
        }
        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
            guard !newValue.isEmpty else { return }
            let picked = newValue
            DispatchQueue.main.async {
                spaceIcon = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
            }
        }
        .sheet(isPresented: $isProfileCreationPresented) {
            ProfileCreationDialog(
                isNameAvailable: { proposed in
                    let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return false }
                    return !browserManager.profileManager.profiles.contains {
                        $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }
                },
                onCreate: { name, icon in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let created = browserManager.profileManager.createProfile(
                        name: trimmed,
                        icon: SumiPersistentGlyph.normalizedProfileIconValue(
                            icon.isEmpty ? SumiPersistentGlyph.profileSystemImageFallback : icon
                        )
                    )
                    selectedProfileId = created.id
                    isProfileCreationPresented = false
                },
                onCancel: {
                    isProfileCreationPresented = false
                }
            )
            .environmentObject(browserManager)
        }
    }

    private var currentProfileName: String {
        guard let profileId = selectedProfileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return browserManager.profileManager.profiles.first?.name ?? "Default"
        }
        return profile.name
    }

    private var currentProfilePickerSymbolName: String {
        guard let profileId = selectedProfileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return SumiPersistentGlyph.resolvedProfileSystemImageName(
                browserManager.profileManager.profiles.first?.icon ?? SumiPersistentGlyph.profileSystemImageFallback
            )
        }
        return SumiPersistentGlyph.resolvedProfileSystemImageName(profile.icon)
    }
}
