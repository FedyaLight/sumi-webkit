//
//  SumiProfilesSettingsPane.swift
//  Sumi
//
//  Profile management (also used in the in-tab settings surface).
//

import AppKit
import SwiftUI

struct SumiProfilesSettingsPane: View {
    @ObservedObject var profileManager: ProfileManager
    let profileInventory: ProfileSettingsInventory
    let requestProfileDeletion: (Profile, String, NSWindow?) -> Void
    @State private var isCreatingProfile = false
    @State private var profileCreationFailed = false
    @State private var usage: [UUID: ProfileUsage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SumiProfilesTable(
                profiles: profileManager.profiles,
                usage: usage,
                retiringProfileIDs: profileManager.retiringProfileIDs,
                onRename: renameProfile,
                onAdd: { isCreatingProfile = true },
                onDelete: startDelete
            )
            .frame(height: 320)
        }
        .sheet(isPresented: $isCreatingProfile) {
            ProfileCreationSheet(
                isNameAvailable: { isProfileNameAvailable($0) },
                onSave: { name in
                    createProfile(name: name)
                },
                onCancel: {
                    isCreatingProfile = false
                }
            )
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
        .onAppear {
            refreshUsage()
        }
    }

    private func usage(for profile: Profile) -> ProfileUsage {
        usage[profile.id] ?? .none
    }

    private func refreshUsage() {
        usage = profileInventory.snapshot()
    }

    private func startDelete(_ profile: Profile, presentationWindow: NSWindow?) {
        guard profileManager.retiringProfileIDs.isEmpty else {
            return
        }
        requestProfileDeletion(
            profile,
            ProfileRetirementImpactPresentation.confirmationMessage(
                for: usage(for: profile)
            ),
            presentationWindow
        )
    }

    private func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isProfileNameAvailable(trimmed) else { return }

        do {
            try profileManager.createProfile(name: trimmed)
            isCreatingProfile = false
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileManager] Profile creation failed: \(error)"
            )
            profileCreationFailed = true
        }
    }

    private func renameProfile(_ profile: Profile, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              isProfileNameAvailable(trimmed, excluding: profile.id)
        else { return false }

        profile.name = trimmed
        profileManager.persistProfiles()
        return true
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
