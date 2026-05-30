import Observation
import SwiftUI

@Observable
final class BasicAuthDialogModel {
    var username: String
    var password: String
    var rememberCredential: Bool
    let host: String

    init(host: String, username: String = "", password: String = "", rememberCredential: Bool = false) {
        self.host = host
        self.username = username
        self.password = password
        self.rememberCredential = rememberCredential
    }
}

@MainActor
final class BasicAuthSheetSession: Identifiable {
    let id = UUID()
    let model: BasicAuthDialogModel
    private let onSubmit: (String, String, Bool) -> Void
    private let onCancel: () -> Void
    private var didComplete = false

    init(
        model: BasicAuthDialogModel,
        onSubmit: @escaping (String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    func submit(username: String, password: String, rememberCredential: Bool) {
        guard didComplete == false else { return }
        didComplete = true
        onSubmit(username, password, rememberCredential)
    }

    func cancel() {
        guard didComplete == false else { return }
        didComplete = true
        onCancel()
    }
}

struct BasicAuthDialog: View {
    @Bindable var model: BasicAuthDialogModel
    let onSubmit: (String, String, Bool) -> Void
    let onCancel: () -> Void

    init(
        model: BasicAuthDialogModel,
        onSubmit: @escaping (String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Form {
                TextField("User name:", text: $model.username)
                SecureField("Password:", text: $model.password)
                Toggle("Remember for this site", isOn: $model.rememberCredential)
            }

            footer
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("The server \(model.host) is requesting credentials.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Sign In") {
                onSubmit(model.username, model.password, model.rememberCredential)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var canSubmit: Bool {
        model.username.isEmpty == false && model.password.isEmpty == false
    }
}
