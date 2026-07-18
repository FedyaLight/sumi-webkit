//
//  ProfilesSettingsView.swift
//  Sumi
//

import AppKit
import SwiftUI

/// Profile management (also used in the in-tab settings surface).
struct SumiProfilesSettingsPane: View {
    @ObservedObject var profileManager: ProfileManager
    let profileInventory: ProfileSettingsInventory
    let deleteProfile: (Profile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfilesSettingsView(
                profileManager: profileManager,
                profileInventory: profileInventory,
                deleteProfile: deleteProfile
            )
        }
    }
}

struct ProfilesSettingsView: View {
    private enum ProfileEditorPresentation: Identifiable {
        case add
        case edit(UUID)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let id):
                return "edit-\(id.uuidString)"
            }
        }
    }

    @ObservedObject var profileManager: ProfileManager
    let profileInventory: ProfileSettingsInventory
    let deleteProfile: (Profile) -> Void
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var profileEditorPresentation: ProfileEditorPresentation?
    @State private var profileCreationFailed = false
    @State private var inventoryRevision = 0

    var body: some View {
        SettingsSection(
            title: "Browsing Profiles",
            subtitle: "Each profile keeps website data, history, and extension state separate."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if profileManager.profiles.isEmpty {
                    SettingsEmptyState(
                        systemImage: "person.2",
                        title: "No Profiles",
                        detail: "Add a profile to keep browsing data separate."
                    )

                    SettingsDivider()

                    profileToolbar
                } else {
                    profileRows

                    SettingsDivider()

                    profileToolbar
                }
            }
        }
        .sheet(item: $profileEditorPresentation) { presentation in
            profileEditorSheet(for: presentation)
                .sumiNativeSurfaceColorScheme()
        }
        .alert("Couldn't Create Profile", isPresented: $profileCreationFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The profile couldn't be saved. No profile was created.")
        }
        .onReceive(profileInventory.updates) { _ in
            inventoryRevision &+= 1
        }
    }

    // MARK: - Helpers

    private var profileRows: some View {
        VStack(spacing: 0) {
            ForEach(profileManager.profiles, id: \.id) { profile in
                ProfileRowView(
                    profile: profile,
                    spacesCount: spacesCount(for: profile),
                    tabsCount: tabsCount(for: profile),
                    canDelete: canDelete(profile),
                    onEdit: { startEdit(profile) },
                    onDelete: { startDelete(profile) }
                )

                if profile.id != profileManager.profiles.last?.id {
                    SettingsDivider()
                        .padding(.leading, 58)
                }
            }
        }
    }

    private var profileToolbar: some View {
        HStack {
            Spacer()
            Button("Add Profile...") {
                profileEditorPresentation = .add
            }
            .buttonStyle(.bordered)
        }
    }

    private func canDelete(_ profile: Profile) -> Bool {
        profileManager.profiles.count > 1
            && profileManager.profiles.contains { $0.id == profile.id }
    }

    private func spacesCount(for profile: Profile) -> Int {
        _ = inventoryRevision
        return profileInventory.spacesCount(profile.id)
    }

    private func tabsCount(for profile: Profile) -> Int {
        _ = inventoryRevision
        return profileInventory.tabsCount(profile.id)
    }

    // MARK: - Actions
    @ViewBuilder
    private func profileEditorSheet(
        for presentation: ProfileEditorPresentation
    ) -> some View {
        switch presentation {
        case .add:
            ProfileEditorSheet(
                mode: .create,
                isNameAvailable: { isProfileNameAvailable($0) },
                onSave: { name in
                    createProfile(name: name)
                },
                onCancel: {
                    profileEditorPresentation = nil
                }
            )
        case .edit(let profileID):
            if let profile = profileManager.profiles.first(where: { $0.id == profileID }) {
                ProfileEditorSheet(
                    mode: .edit,
                    initialName: profile.name,
                    isNameAvailable: {
                        isProfileNameAvailable($0, excluding: profile.id)
                    },
                    onSave: { name in
                        updateProfile(profile, name: name)
                    },
                    onCancel: {
                        profileEditorPresentation = nil
                    }
                )
            } else {
                EmptyView()
            }
        }
    }

    private func startEdit(_ profile: Profile) {
        profileEditorPresentation = .edit(profile.id)
    }

    private func startDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(profile.name)”?"
        alert.informativeText = deleteConfirmationMessage(for: profile)
        if let icon = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete Profile"
        ) {
            alert.icon = icon
        }

        let deleteButton = alert.addButton(withTitle: "Delete Profile")
        deleteButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        alert.sumiApplyNativeSurfaceAppearance(themeContext: themeContext)
        if alert.runModal() == .alertFirstButtonReturn {
            confirmDelete(profile)
        }
    }

    private func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isProfileNameAvailable(trimmed) else { return }

        do {
            try profileManager.createProfile(name: trimmed)
            profileEditorPresentation = nil
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileManager] Profile creation failed: \(error)"
            )
            profileCreationFailed = true
        }
    }

    private func updateProfile(_ profile: Profile, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              isProfileNameAvailable(trimmed, excluding: profile.id)
        else { return }

        profile.name = trimmed
        profileManager.persistProfiles()
        profileEditorPresentation = nil
    }

    private func confirmDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }
        deleteProfile(profile)
    }

    private func isProfileNameAvailable(
        _ proposedName: String,
        excluding excludedProfileID: UUID? = nil
    ) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !profileManager.profiles.contains {
            $0.id != excludedProfileID
                && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func deleteConfirmationMessage(for profile: Profile) -> String {
        let spaces = spacesCount(for: profile)
        let tabs = tabsCount(for: profile)
        let spaceText = spaces == 1 ? "1 space" : "\(spaces) spaces"
        let tabText = tabs == 1 ? "1 tab" : "\(tabs) tabs"
        return "\(spaceText) and \(tabText) that use this profile will move to another profile. Website data stored for this profile will be deleted."
    }
}
