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
        StandardDialog(
            header: {
                DialogHeader(
                    icon: "lock.circle",
                    title: "Authentication Required",
                    subtitle: "The server \(model.host) is requesting credentials."
                )
            },
            content: {
                dialogContent
            },
            footer: {
                dialogFooter
            }
        )
        .padding(20)
    }

    private var dialogContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("User name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                SumiTextField(
                    text: $model.username,
                    placeholder: "Enter user name",
                    iconName: "person"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                SecureField("Enter password", text: $model.password)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Toggle(isOn: $model.rememberCredential) {
                Text("Remember for this site")
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 4)
    }

    private var dialogFooter: DialogFooter {
        let canSubmit = !model.username.isEmpty && !model.password.isEmpty

        return DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Sign In",
                    iconName: "arrow.right.circle",
                    variant: .primary,
                    keyboardShortcut: .return,
                    isEnabled: canSubmit,
                    action: {
                        onSubmit(model.username, model.password, model.rememberCredential)
                    }
                )
            ]
        )
    }
}
