import SwiftUI

struct ProfileCreationSheet: View {
    let isNameAvailable: (String) -> Bool
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var profileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Profile")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $profileName)
                .textFieldStyle(.roundedBorder)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Add") {
                    onSave(trimmedName)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 420)
    }

    private var trimmedName: String {
        profileName.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
