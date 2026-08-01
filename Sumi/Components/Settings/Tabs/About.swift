//
//  About.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SettingsAboutTab: View {
    @ObservedObject private var updaterService: SumiUpdaterService
    @State private var didRequestInitialUpdateCheck = false

    private let metadata = SumiAppVersionMetadata.resolve()

    init(updaterService: SumiUpdaterService) {
        self._updaterService = ObservedObject(wrappedValue: updaterService)
    }

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
        VStack(alignment: .leading, spacing: 20) {
            SumiAboutStatusPanel(
                viewModel: updateViewModel,
                appIconImage: appIconImage
            )

            SumiAboutVersionUpdatePanel(
                viewModel: updateViewModel,
                onRetry: { updaterService.checkForUpdatesFromAboutView() }
            )
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

private enum SumiAboutLayout {
    static let cardHorizontalPadding: CGFloat = 18
    static let cardVerticalPadding: CGFloat = 18
    static let appIconSize: CGFloat = 76
    static let appIconVisibleLeadingCorrection: CGFloat = -10
}

private struct SumiAboutCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SumiAboutLayout.cardVerticalPadding)
            .padding(.horizontal, SumiAboutLayout.cardHorizontalPadding)
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
}

private struct SumiAboutStatusPanel: View {
    let viewModel: SumiAboutUpdateViewModel
    let appIconImage: Image

    var body: some View {
        SumiAboutCard {
            HStack(alignment: .center, spacing: 18) {
                appIconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: SumiAboutLayout.appIconSize, height: SumiAboutLayout.appIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .offset(x: SumiAboutLayout.appIconVisibleLeadingCorrection)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let statusDetail {
                        Text(statusDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var statusTitle: String {
        switch viewModel.panelState {
        case .ready, .checking:
            return "Checking for updates..."
        case .upToDate:
            return "Sumi is up to date"
        case .updateAvailable(let update):
            return "\(update.versionLine) is available"
        case .checkFailed:
            return "Couldn't check for updates"
        case .unavailable:
            return "Updates unavailable"
        }
    }

    private var statusDetail: String? {
        switch viewModel.panelState {
        case .ready, .checking:
            return nil
        case .upToDate:
            return nil
        case .updateAvailable:
            return "Download and install the update with Sparkle."
        case .checkFailed(let message), .unavailable(let message):
            return message
        }
    }
}

private struct SumiAboutVersionUpdatePanel: View {
    let viewModel: SumiAboutUpdateViewModel
    let onRetry: () -> Void

    var body: some View {
        SumiAboutCard {
            HStack(alignment: .center, spacing: 10) {
                SumiAboutStatusBadge(kind: statusBadgeKind)

                Text(viewModel.metadata.versionLine)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                SettingsPillBadge(title: viewModel.channelDisplayName.uppercased())

                Spacer(minLength: 16)

                actionButton
            }
        }
    }

    private var statusBadgeKind: SumiAboutStatusBadge.Kind {
        switch viewModel.panelState {
        case .ready, .checking:
            return .progress
        case .upToDate:
            return .checkmark
        case .updateAvailable:
            return .download
        case .checkFailed:
            return .warning
        case .unavailable:
            return .info
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.panelState {
        case .ready, .checking:
            Button("Check for Updates", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(true)
        case .upToDate:
            Button("Check for Updates", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(!viewModel.checkButtonIsEnabled)
        case .updateAvailable(let update):
            Button("Update", action: viewModel.checkForUpdates)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .disabled(!viewModel.checkButtonIsEnabled)
                .accessibilityLabel("Update to \(update.versionLine)")
        case .checkFailed(let message):
            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(!viewModel.checkButtonIsEnabled)
                .accessibilityHint(message)
        case .unavailable:
            Button("Check for Updates", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(true)
        }
    }
}

private struct SumiAboutStatusBadge: View {
    enum Kind: Equatable {
        case progress
        case checkmark
        case download
        case warning
        case info
    }

    let kind: Kind

    var body: some View {
        Group {
            if kind == .progress {
                ProgressView()
                    .controlSize(.small)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: backgroundColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )

                    Image(systemName: systemImageName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private var systemImageName: String {
        switch kind {
        case .progress:
            return "clock"
        case .checkmark:
            return "checkmark"
        case .download:
            return "arrow.down"
        case .warning:
            return "exclamationmark"
        case .info:
            return "info"
        }
    }

    private var backgroundColors: [Color] {
        switch kind {
        case .progress:
            return [
                Color(nsColor: .systemGray),
                Color(nsColor: .systemGray),
            ]
        case .checkmark:
            return [
                Color(nsColor: NSColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)),
                Color(nsColor: NSColor(red: 46 / 255, green: 180 / 255, blue: 80 / 255, alpha: 1)),
            ]
        case .download:
            return [
                Color(nsColor: .systemBlue),
                Color(nsColor: .controlAccentColor),
            ]
        case .warning:
            return [
                Color(nsColor: .systemOrange),
                Color(nsColor: NSColor(red: 210 / 255, green: 120 / 255, blue: 24 / 255, alpha: 1)),
            ]
        case .info:
            return [
                Color(nsColor: .systemGray),
                Color(nsColor: .secondaryLabelColor),
            ]
        }
    }
}
