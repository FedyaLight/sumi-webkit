//
//  About.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SettingsAboutTab: View {
    @ObservedObject private var updaterService = SumiUpdaterService.shared
    @State private var didRequestInitialUpdateCheck = false

    private let metadata = SumiAppVersionMetadata.resolve()

    private var appIconImage: Image {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
    }

    private var updateViewModel: SumiAboutUpdateViewModel {
        SumiAboutUpdateViewModel(
            metadata: metadata,
            state: updaterService.state,
            checkForUpdates: { updaterService.startUpdateFromSidebarNotice() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SumiAboutVersionPanel(
                metadata: metadata,
                channelName: updateViewModel.channelDisplayName,
                appIconImage: appIconImage
            )

            SumiAboutUpdatePanel(
                viewModel: updateViewModel,
                onRetry: { updaterService.checkForUpdatesFromAboutView() }
            )

            SettingsSection(
                title: "Protection Data Notices",
                subtitle: "Generated trackingNetwork bundle data may be derived from DuckDuckGo Tracker Radar / TDS."
            ) {
                Text("DuckDuckGo Tracker Radar / TDS tracking data is licensed under CC BY-NC-SA 4.0. Non-commercial use and share-alike terms apply to generated protection bundle data.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            requestInitialUpdateCheckIfNeeded()
        }
    }

    private func requestInitialUpdateCheckIfNeeded() {
        guard didRequestInitialUpdateCheck == false else { return }
        didRequestInitialUpdateCheck = true
        updaterService.checkForUpdatesFromAboutView()
    }
}

private struct SumiAboutVersionPanel: View {
    let metadata: SumiAppVersionMetadata
    let channelName: String
    let appIconImage: Image

    var body: some View {
        SettingsSection(
            title: metadata.displayName,
            subtitle: "Current version"
        ) {
            HStack(alignment: .center, spacing: 16) {
                appIconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(metadata.versionLine)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(channelName.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SettingsSurfaceStyle.fieldBackground)
                            )
                    }

                    Text(metadata.buildLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct SumiAboutUpdatePanel: View {
    let viewModel: SumiAboutUpdateViewModel
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: SettingsSurfaceStyle.groupedCornerRadius, style: .continuous)
                .fill(SettingsSurfaceStyle.groupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsSurfaceStyle.groupedCornerRadius, style: .continuous)
                .strokeBorder(SettingsSurfaceStyle.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch viewModel.panelState {
        case .ready, .checking:
            SumiAboutUpdateStatusRow(
                systemImage: nil,
                title: "Checking for updates...",
                subtitle: "Sumi is looking for the latest Alpha build.",
                progress: true
            )

        case .upToDate:
            SumiAboutUpdateStatusRow(
                systemImage: "checkmark.circle.fill",
                title: "Installed latest version",
                subtitle: "\(viewModel.metadata.displayName) \(viewModel.metadata.shortVersion) is current.",
                symbolStyle: .green
            )

        case .updateAvailable(let update):
            HStack(alignment: .center, spacing: 14) {
                SumiAboutUpdateStatusRow(
                    systemImage: "arrow.down.circle.fill",
                    title: "\(update.versionLine) is available",
                    subtitle: "Download and install the update with Sparkle.",
                    symbolStyle: .accentColor
                )

                Spacer(minLength: 16)

                Button("Update", action: viewModel.checkForUpdates)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!viewModel.checkButtonIsEnabled)
            }

        case .checkFailed(let message):
            HStack(alignment: .center, spacing: 14) {
                SumiAboutUpdateStatusRow(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Couldn't check for updates",
                    subtitle: message,
                    symbolStyle: .yellow
                )

                Spacer(minLength: 16)

                Button("Try Again", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!viewModel.checkButtonIsEnabled)
            }

        case .unavailable(let message):
            SumiAboutUpdateStatusRow(
                systemImage: "info.circle.fill",
                title: "Updates unavailable",
                subtitle: message,
                symbolStyle: .secondary
            )
        }
    }
}

private struct SumiAboutUpdateStatusRow: View {
    let systemImage: String?
    let title: String
    let subtitle: String
    var progress = false
    var symbolStyle: Color = .secondary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if progress {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(symbolStyle)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
