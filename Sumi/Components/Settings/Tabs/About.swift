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
        }
    }
}
