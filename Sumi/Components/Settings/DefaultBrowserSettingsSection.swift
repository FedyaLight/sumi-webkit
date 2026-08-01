import AppKit
import SwiftUI

struct DefaultBrowserSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase

    private let service: SumiDefaultBrowserService

    @State private var status: SumiDefaultBrowserStatus = .unknown
    @State private var isSettingDefaultBrowser = false

    init(service: SumiDefaultBrowserService) {
        self.service = service
    }

    var body: some View {
        SettingsSection(title: "Default Browser") {
            SettingsRow(
                title: "Make Sumi your default browser",
                subtitle: currentDefaultBrowserLine,
                systemImage: "safari"
            ) {
                Button("Make Default") {
                    makeDefault()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canMakeDefault)
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

        Task {
            _ = await service.requestBecomeDefault()
            isSettingDefaultBrowser = false
            refreshStatus()
        }
    }
}
