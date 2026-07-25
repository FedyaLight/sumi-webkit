import AppKit
import SwiftUI

/// Explains why a browser could not be read and offers the two ways forward:
/// grant Full Disk Access, or hand Sumi the file directly.
///
/// The System Settings URL is kept local rather than added to the permission
/// kind enum: this is a one-off remedy in an import flow, not a web permission
/// Sumi tracks per site.
struct SumiFullDiskAccessExplainerView: View {
    let browser: SumiDetectedBrowser
    let onDismiss: () -> Void

    private static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isFullDiskAccess {
                VStack(alignment: .leading, spacing: 6) {
                    stepLabel(1, "Open Privacy & Security → Full Disk Access.")
                    stepLabel(2, "Turn on Sumi in the list.")
                    stepLabel(3, "Quit and reopen Sumi, then try the import again.")
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Close", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                if isFullDiskAccess, let url = Self.fullDiskAccessSettingsURL {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(url)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 260)
    }

    private var isFullDiskAccess: Bool {
        browser.accessIssue == .fullDiskAccessRequired
    }

    private var title: String {
        isFullDiskAccess ? "Sumi needs Full Disk Access" : "\(browser.displayName) cannot be imported"
    }

    private var explanation: String {
        guard isFullDiskAccess else {
            return browser.accessIssue?.explanation ?? "This browser's data could not be read."
        }
        return "macOS keeps \(browser.displayName)'s bookmarks and history in a protected folder. "
            + "Until Sumi has Full Disk Access it cannot see them — which is also why "
            + "\(browser.displayName) may look like it is not installed."
    }

    private func stepLabel(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }
}
