import AppKit
import SwiftUI

struct DefaultBrowserSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase

    private let service: SumiDefaultBrowserService

    @State private var status: SumiDefaultBrowserStatus = .unknown
    @State private var isSettingDefaultBrowser = false
    @State private var errorMessage: String?

    init(service: SumiDefaultBrowserService = .shared) {
        self.service = service
    }

    var body: some View {
        SettingsSection(title: "Default Browser") {
            SettingsRow(
                title: "Make Sumi your default browser",
                subtitle: currentDefaultBrowserLine
            ) {
                Button("Make Default") {
                    makeDefault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canMakeDefault)
            }

            if let errorMessage {
                SettingsDivider()

                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshStatus)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshStatus()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)
        ) { _ in
            refreshStatus()
        }
    }

    private var canMakeDefault: Bool {
        service.canSetProgrammatically && status != .isDefault && !isSettingDefaultBrowser
    }

    private var currentDefaultBrowserLine: String {
        switch status {
        case .isDefault:
            return "Current default browser: Sumi"
        case .other(let displayName):
            return "Current default browser: \(displayName)"
        case .unknown, .sandboxed:
            return "Current default browser: Unknown"
        }
    }

    private func refreshStatus() {
        status = service.currentStatus()
    }

    private func makeDefault() {
        guard canMakeDefault else { return }

        isSettingDefaultBrowser = true
        errorMessage = nil

        Task {
            let result = await service.requestBecomeDefault()
            isSettingDefaultBrowser = false
            refreshStatus()

            switch result {
            case .success:
                errorMessage = nil
            case .failure(let error):
                switch error {
                case .sandboxed:
                    errorMessage = "Sumi cannot change the default browser while App Sandbox is enabled."
                case .systemError(let message):
                    errorMessage = message
                }
            }
        }
    }
}
