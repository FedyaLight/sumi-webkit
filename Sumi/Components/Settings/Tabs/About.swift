//
//  About.swift
//  Sumi
//

import SwiftUI

private enum SumiAppMetadata {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Sumi"
    }

    static var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "Unknown"
    }

    static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "Unknown"
    }
}

struct SettingsAboutTab: View {
    @EnvironmentObject private var browserManager: BrowserManager

    private var updateButtonTitle: String {
        if browserManager.updateAvailability?.isDownloaded == true {
            return "Install Update"
        }
        return "Check for Updates..."
    }

    private var updateStatusText: String {
        guard let availability = browserManager.updateAvailability else {
            return "Use Sparkle to check for the latest Sumi release from within Settings."
        }
        if availability.isDownloaded {
            return "A downloaded update is ready to install when you apply it."
        }
        return "A new Sumi update is available."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionCard(
                title: "About Sumi",
                subtitle: "Version \(SumiAppMetadata.shortVersion) / Build \(SumiAppMetadata.buildNumber)"
            ) {
                HStack(alignment: .center, spacing: 16) {
                    Image("sumi-logo-1024")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(SumiAppMetadata.displayName)
                            .font(.title3.weight(.semibold))

                        Text("Version \(SumiAppMetadata.shortVersion)")
                            .foregroundStyle(.primary)

                        Text("Build \(SumiAppMetadata.buildNumber)")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            if SumiUpdateConfiguration.isConfigured {
                SettingsSectionCard(
                    title: "Updates",
                    subtitle: "Check for new Sumi releases and install downloaded updates"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(updateStatusText)
                            .foregroundStyle(.secondary)

                        Button(updateButtonTitle) {
                            if browserManager.updateAvailability?.isDownloaded == true {
                                browserManager.installPendingUpdateIfAvailable()
                            } else {
                                browserManager.checkForUpdates()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}
