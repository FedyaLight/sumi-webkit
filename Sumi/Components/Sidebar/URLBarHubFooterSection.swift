import SwiftUI

struct SumiFooterSecurityStatus: View {
    let securityState: SiteControlsSnapshot.SecurityState

    var body: some View {
        HStack(spacing: 8) {
            SumiZenChromeIcon(
                iconName: securityState.chromeIconName,
                fallbackSystemName: securityState.fallbackSystemName,
                size: 16,
                tint: labelColor
            )
            Text(securityState.footerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(URLBarHubNativeStyle.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var labelColor: Color {
        securityState == .notSecure ? URLBarHubNativeStyle.destructiveText : URLBarHubNativeStyle.primaryText
    }
}
struct SumiFooterSiteSettingsButton: View {
    let siteSettingsAction: () -> Void
    let clearSiteDataAction: () -> Void
    let resetPermissionsAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: siteSettingsAction) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Site Settings")
        .accessibilityLabel("Site Settings")
        .accessibilityIdentifier("urlhub-site-settings-button")
        .contextMenu {
            Button("Site Settings", action: siteSettingsAction)
            Button("Clear Site Data", action: clearSiteDataAction)
            Divider()
            Button("Reset Permissions to Default", action: resetPermissionsAction)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct SumiFooterBoostButton: View {
    let boosts: [SumiBoost]
    let activeBoostId: UUID?
    let action: () -> Void
    let createAction: () -> Void
    let toggleAction: (SumiBoost) -> Void
    let editAction: (SumiBoost) -> Void

    @State private var isHovered = false

    private var isActive: Bool {
        activeBoostId != nil
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isActive ? "paintbrush.pointed.fill" : "paintbrush.pointed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? URLBarHubNativeStyle.accentBackground : URLBarHubNativeStyle.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Boosts")
        .accessibilityLabel("Boosts")
        .accessibilityIdentifier("urlhub-boosts-button")
        .contextMenu {
            Button("Create Boost", action: createAction)

            if !boosts.isEmpty {
                Divider()
            }

            ForEach(boosts) { boost in
                Button(activeBoostId == boost.id ? "Disable \(boost.data.boostName)" : "Enable \(boost.data.boostName)") {
                    toggleAction(boost)
                }
                Button("Edit \(boost.data.boostName)") {
                    editAction(boost)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
