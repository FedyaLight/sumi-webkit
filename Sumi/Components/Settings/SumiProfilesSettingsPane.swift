//
//  SumiProfilesSettingsPane.swift
//  Sumi
//
//  Profile management (also used in the in-tab settings surface).
//

import SwiftUI

struct SumiProfilesSettingsPane: View {
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
    let requestProfileDeletion: (Profile, String) -> Void
    @State private var profileEditorPresentation: ProfileEditorPresentation?
    @State private var profileCreationFailed = false
    @State private var usage: [UUID: ProfileUsage] = [:]

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
                } else {
                    profileRows
                }

                SettingsDivider()

                profileToolbar
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
        .onReceive(profileManager.$profiles) { _ in
            refreshUsage()
        }
        .onReceive(profileInventory.updates) { _ in
            refreshUsage()
        }
    }

    // MARK: - Helpers

    private var profileRows: some View {
        VStack(spacing: 0) {
            ForEach(profileManager.profiles) { profile in
                ProfileRowView(
                    profile: profile,
                    usage: usage(for: profile),
                    isDeleting: profileManager.retiringProfileIDs.contains(
                        profile.id
                    ),
                    canDelete: profileManager.retiringProfileIDs.isEmpty,
                    onEdit: { startEdit(profile) },
                    onDelete: { startDelete(profile) }
                )

                if profile.id != profileManager.profiles.last?.id {
                    SettingsDivider()
                        .padding(.leading, 10)
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
            .disabled(profileManager.retiringProfileIDs.isEmpty == false)
        }
    }

    private func usage(for profile: Profile) -> ProfileUsage {
        usage[profile.id] ?? .none
    }

    private func refreshUsage() {
        usage = profileInventory.snapshot()
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
        guard profileManager.retiringProfileIDs.contains(profile.id) == false
        else { return }
        profileEditorPresentation = .edit(profile.id)
    }

    private func startDelete(_ profile: Profile) {
        guard profileManager.retiringProfileIDs.isEmpty else {
            return
        }
        requestProfileDeletion(
            profile,
            ProfileRetirementImpactPresentation.confirmationMessage(
                for: usage(for: profile)
            )
        )
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
}
