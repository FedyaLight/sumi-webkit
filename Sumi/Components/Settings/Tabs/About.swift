//
//  About.swift
//  Sumi
//

import AppKit
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
    private var appIconImage: Image {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "About Sumi",
                subtitle: "Version \(SumiAppMetadata.shortVersion) / Build \(SumiAppMetadata.buildNumber)"
            ) {
                HStack(alignment: .center, spacing: 16) {
                    appIconImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(SumiAppMetadata.displayName)
                                .font(.title3.weight(.semibold))

                            Text("ALPHA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.orange, in: Capsule())
                        }

                        Text("Version \(SumiAppMetadata.shortVersion)")
                            .foregroundStyle(.primary)

                        Text("Build \(SumiAppMetadata.buildNumber)")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            SettingsSection(
                title: "Protection Data Notices",
                subtitle: "Generated trackingNetwork bundle data may be derived from DuckDuckGo Tracker Radar / TDS."
            ) {
                Text("DuckDuckGo Tracker Radar / TDS tracking data is licensed under CC BY-NC-SA 4.0. Non-commercial use and share-alike terms apply to generated protection bundle data.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
