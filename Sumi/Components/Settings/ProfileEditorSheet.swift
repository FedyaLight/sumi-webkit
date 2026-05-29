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
    let originalIcon: String
    let isNameAvailable: (String) -> Bool
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var profileName: String
    @State private var profileIcon: String
    @StateObject private var emojiManager = EmojiPickerManager()
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(
        mode: Mode,
        initialName: String = "",
        initialIcon: String = SumiProfileIcon.defaultIcon,
        isNameAvailable: @escaping (String) -> Bool,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.originalName = initialName
        self.originalIcon = SumiProfileIcon.storedValue(initialIcon)
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
        _profileName = State(initialValue: initialName)
        _profileIcon = State(initialValue: SumiProfileIcon.storedValue(initialIcon))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                Button(action: openEmojiPicker) {
                    profileIconPreview
                }
                .buttonStyle(.plain)
                .background(EmojiPickerAnchor(manager: emojiManager))
                .help("Change Profile Icon")
                .accessibilityLabel("Change Profile Icon")

                TextField("Name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
            }

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
                    onSave(trimmedName, storedIcon)
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

    private var storedIcon: String {
        SumiProfileIcon.storedValue(profileIcon)
    }

    private var profileIconPreview: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))

            SumiProfileIconView(
                icon: storedIcon,
                font: .system(size: 26, weight: .medium)
            )
            .foregroundStyle(.primary)
        }
        .frame(width: 48, height: 48)
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(Circle())
    }

    private var hasChanges: Bool {
        switch mode {
        case .create:
            return true
        case .edit:
            return trimmedName != originalName || storedIcon != originalIcon
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

    private func openEmojiPicker() {
        emojiManager.selectedEmoji = storedIcon
        emojiManager.toggle(
            settings: sumiSettings,
            themeContext: themeContext
        ) { picked in
            let trimmed = picked.trimmingCharacters(in: .whitespacesAndNewlines)
            profileIcon = trimmed.isEmpty
                ? SumiProfileIcon.defaultIcon
                : SumiProfileIcon.storedValue(trimmed)
        }
    }
}
