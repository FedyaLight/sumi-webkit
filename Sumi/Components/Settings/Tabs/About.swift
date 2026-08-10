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
            SumiAboutUpdatePanel(
                viewModel: updateViewModel,
                appIconImage: appIconImage,
                onRetry: { updaterService.checkForUpdatesFromAboutView() }
            )

            SumiAboutLinksPanel(
                changelogURL: SumiUpdateReleaseNotesURL.url(
                    forDisplayVersion: metadata.shortVersion
                )
            )
        }
        .onAppear {
            requestInitialUpdateCheckIfNeeded()
        }
    }

    private func requestInitialUpdateCheckIfNeeded() {
        guard didRequestInitialUpdateCheck == false else { return }
        didRequestInitialUpdateCheck = true
        guard case .none = updaterService.state.availability else { return }
        updaterService.checkForUpdatesFromAboutView()
    }
}

private enum SumiAboutLayout {
    static let cardHorizontalPadding: CGFloat = 18
    static let cardVerticalPadding: CGFloat = 18
    static let appIconSize: CGFloat = 56
    static let linkIconSize: CGFloat = 28
    static let linkIconCornerRadius: CGFloat = 8
    static let linkRowCornerRadius: CGFloat = 9
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

private struct SumiAboutLinksPanel: View {
    let changelogURL: URL

    var body: some View {
        SumiAboutCard {
            VStack(spacing: 0) {
                SumiAboutLinkRow(
                    title: "Changelog",
                    systemImageName: "heart.circle.fill",
                    url: changelogURL,
                    foreground: .secondary
                )

                SumiAboutLinkRow(
                    title: "Support us",
                    systemImageName: "gift",
                    url: SumiExternalLinks.support,
                    foreground: .secondary
                )

                SumiAboutLinkRow(
                    title: "Something broke?",
                    systemImageName: "exclamationmark.bubble",
                    url: SumiExternalLinks.issues,
                    foreground: .secondary
                )
            }
        }
    }
}

private struct SumiAboutLinkRow: View {
    let title: LocalizedStringResource
    let systemImageName: String
    let url: URL
    let foreground: Color

    @State private var isHovered = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(SettingsThemeTokens.Typography.aboutLinkIcon)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foreground)
                    .frame(
                        width: SumiAboutLayout.linkIconSize,
                        height: SumiAboutLayout.linkIconSize
                    )
                    .background {
                        RoundedRectangle(
                            cornerRadius: SumiAboutLayout.linkIconCornerRadius,
                            style: .continuous
                        )
                        .fill(foreground.opacity(0.11))
                    }

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(foreground)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.right")
                    .font(SettingsThemeTokens.Typography.aboutExternalLinkIcon)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(
                    cornerRadius: SumiAboutLayout.linkRowCornerRadius,
                    style: .continuous
                )
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: SumiAboutLayout.linkRowCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(Text(title))
    }
}

private struct SumiAboutUpdatePanel: View {
    let viewModel: SumiAboutUpdateViewModel
    let appIconImage: Image
    let onRetry: () -> Void

    var body: some View {
        SumiAboutCard {
            HStack(alignment: .center, spacing: 14) {
                appIconImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: SumiAboutLayout.appIconSize, height: SumiAboutLayout.appIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let statusDetail {
                            Text(statusDetail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    versionRow
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var versionRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(viewModel.metadata.versionLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            SettingsPillBadge(title: viewModel.channelDisplayName.uppercased())

            Spacer(minLength: 16)

            actionButton
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
            return nil
        case .checkFailed(let message), .unavailable(let message):
            return message
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
