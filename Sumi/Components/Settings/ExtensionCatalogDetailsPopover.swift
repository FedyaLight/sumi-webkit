//
//  ExtensionCatalogDetailsPopover.swift
//  Sumi
//

import AppKit
import SwiftUI

struct ExtensionCatalogDetailsPopover: View {
    let extensionRecord: InstalledExtension
    let siteAccessPolicy: SafariExtensionSiteAccessPolicy?
    let isBusy: Bool
    @Binding var defaultSiteAccess: SafariExtensionSiteAccessLevel
    @Binding var privateAccessAllowed: Bool
    let onConfiguredSiteAccessChanged: (
        String,
        SafariExtensionSiteAccessLevel
    ) -> Void
    let onOpenOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if showsWarnings {
                detailSection("Warnings") {
                    VStack(alignment: .leading, spacing: 8) {
                        if extensionRecord.activationSummary.broadScope {
                            warningRow(
                                systemImage: "hand.raised.fill",
                                text: "Can read and change website data on allowed websites."
                            )
                        }
                        if extensionRecord.legacyManifestMayUseMoreEnergy {
                            warningRow(
                                systemImage: "battery.100percent.bolt",
                                text: InstalledExtensionRecord.legacyManifestWarningTooltip
                            )
                        }
                    }
                }
            }

            if showsWebsiteAccessControls {
                detailSection("Website Access") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("Other Websites")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: $defaultSiteAccess) {
                                ForEach(SafariExtensionSiteAccessLevel.allCases) { access in
                                    Text(access.title).tag(access)
                                }
                            }
                            .settingsMenuPicker(width: 112)
                            .disabled(isBusy)
                        }

                        if configuredSiteRules.isEmpty == false {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Configured Websites")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(configuredSiteRules) { rule in
                                    HStack(spacing: 10) {
                                        Text(displayName(for: rule.matchPattern))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(
                                                maxWidth: .infinity,
                                                alignment: .leading
                                            )

                                        Picker(
                                            "",
                                            selection: configuredSiteAccessBinding(for: rule)
                                        ) {
                                            ForEach(SafariExtensionSiteAccessLevel.allCases) { access in
                                                Text(access.title).tag(access)
                                            }
                                        }
                                        .settingsMenuPicker(width: 112)
                                        .disabled(isBusy)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if extensionRecord.incognitoMode.allowsPrivateAccess {
                detailSection("Private Access") {
                    Toggle(
                        "Allow in Private Browsing",
                        isOn: $privateAccessAllowed
                    )
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }

            detailSection("Settings") {
                if extensionRecord.hasOptionsPage {
                    Button("Open Extension Settings") {
                        onOpenOptions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(
                        "extension-open-options-\(extensionRecord.id)"
                    )
                    .disabled(isBusy || extensionRecord.isEnabled == false)
                } else {
                    Text("No extension settings page.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let iconPath = ExtensionManifestIconResolver.iconPath(for: extensionRecord),
                   let image = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(extensionRecord.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Version \(extensionRecord.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsWarnings: Bool {
        extensionRecord.activationSummary.broadScope
            || extensionRecord.legacyManifestMayUseMoreEnergy
    }

    private var showsWebsiteAccessControls: Bool {
        extensionRecord.activationSummary.matchPatternStrings.isEmpty == false
            || optionalHostPermissionStrings.isEmpty == false
            || optionalPermissionHostPatternStrings.isEmpty == false
    }

    private var optionalHostPermissionStrings: [String] {
        extensionRecord.manifest["optional_host_permissions"] as? [String] ?? []
    }

    private var optionalPermissionHostPatternStrings: [String] {
        (extensionRecord.manifest["optional_permissions"] as? [String] ?? [])
            .filter {
                $0 == "<all_urls>"
                    || $0.hasPrefix("http://")
                    || $0.hasPrefix("https://")
                    || $0.hasPrefix("*://")
            }
    }

    private var configuredSiteRules: [SafariExtensionSiteAccessRule] {
        siteAccessPolicy?.siteRules ?? []
    }

    private func configuredSiteAccessBinding(
        for rule: SafariExtensionSiteAccessRule
    ) -> Binding<SafariExtensionSiteAccessLevel> {
        Binding(
            get: {
                configuredSiteRules
                    .first { $0.matchPattern == rule.matchPattern }?
                    .access ?? rule.access
            },
            set: { access in
                guard access != rule.access else { return }
                onConfiguredSiteAccessChanged(rule.matchPattern, access)
            }
        )
    }

    private func displayName(for matchPattern: String) -> String {
        guard let url = URL(string: matchPattern),
              let host = url.host,
              host.isEmpty == false
        else {
            return matchPattern
        }
        return host
    }

    private func warningRow(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
        }
        .font(.caption)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
