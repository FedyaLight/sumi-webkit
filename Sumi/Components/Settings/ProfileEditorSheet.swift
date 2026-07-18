//
//  ProfileEditorSheet.swift
//  Sumi
//
//  Native SwiftUI sheet for adding and editing browsing profiles.
//

import SwiftUI

struct ProfileEditorSheet: View {
    enum Mode {
        case create
        case edit

        var title: String {
            switch self {
            case .create: return "Add Profile"
            case .edit: return "Edit Profile"
            }
        }

        var primaryActionTitle: String {
            switch self {
            case .create: return "Add"
            case .edit: return "Save"
            }
        }
    }

    let mode: Mode
    let originalName: String
    let isNameAvailable: (String) -> Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var profileName: String

    init(
        mode: Mode,
        initialName: String = "",
        isNameAvailable: @escaping (String) -> Bool,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.originalName = initialName
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
        _profileName = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title2.weight(.semibold))

            TextField("Name", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .font(SettingsThemeTokens.Typography.profileNameField)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(mode.primaryActionTitle) {
                    onSave(trimmedName)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var trimmedName: String {
        profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        switch mode {
        case .create:
            return true
        case .edit:
            return trimmedName != originalName
        }
    }

    private var validationMessage: String? {
        guard !trimmedName.isEmpty else {
            return "Enter a profile name."
        }
        guard isNameAvailable(trimmedName) else {
            return "A profile with this name already exists."
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && hasChanges
    }
}
