import SwiftUI

struct URLHubPermissionInlineRow: View {
    private enum IconState {
        case neutral
        case on
        case off
    }

    private struct IconVisual {
        let iconName: String?
        let fallbackSystemName: String
        let showsSlash: Bool
    }

    let row: SumiCurrentSitePermissionRow
    let onCycle: () -> Void
    let onSelect: (SumiCurrentSitePermissionOption) -> Void
    let onOpenSystemSettings: () -> Void

    @State private var isHovered = false

    private var canCycle: Bool {
        row.isEditable && row.disabledReason == nil && !row.availableOptions.isEmpty
    }

    private var iconState: IconState {
        switch row.currentOption {
        case .allow, .allowAll:
            return .on
        case .block, .blockAudible, .blockAll:
            return .off
        case .ask, .default, nil:
            return .neutral
        }
    }

    var body: some View {
        Group {
            if canCycle {
                Button(action: onCycle) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .opacity(row.disabledReason == nil ? 1 : 0.55)
        .contextMenu {
            if !row.availableOptions.isEmpty {
                ForEach(row.availableOptions, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Label(
                            option.title,
                            systemImage: option == row.currentOption ? "checkmark" : "circle"
                        )
                    }
                }
            }
            if row.showsSystemSettingsAction {
                Divider()
                Button("Open System Settings", action: onOpenSystemSettings)
            }
        }
        .onHover { hovering in
            guard canCycle else {
                isHovered = false
                return
            }
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("urlhub-permission-row-\(row.id)")
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconCapsuleFill)
                    .scaleEffect(isHovered ? 1.05 : 1)

                ZStack {
                    SumiZenChromeIcon(
                        iconName: iconVisual.iconName,
                        fallbackSystemName: iconVisual.fallbackSystemName,
                        size: 16,
                        tint: URLBarHubNativeStyle.primaryText
                    )

                    if iconVisual.showsSlash {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(URLBarHubNativeStyle.primaryText)
                            .frame(width: 2, height: 23)
                            .rotationEffect(.degrees(-42))
                            .shadow(color: URLBarHubNativeStyle.controlBackground, radius: 0, x: 1, y: 0)
                    }
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    row.title,
                    font: .system(size: 13, weight: .medium),
                    color: URLBarHubNativeStyle.primaryText
                )
                if let status = row.statusLines.first {
                    URLBarFadingText(
                        status,
                        font: .system(size: 11.5),
                        color: URLBarHubNativeStyle.secondaryText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var iconCapsuleFill: Color {
        if isHovered {
            return URLBarHubNativeStyle.hoveredControlBackground
        }
        switch iconState {
        case .on:
            return URLBarHubNativeStyle.hoveredControlBackground
        case .neutral, .off:
            return URLBarHubNativeStyle.controlBackground
        }
    }

    private var iconVisual: IconVisual {
        switch iconState {
        case .neutral:
            return IconVisual(
                iconName: row.iconName,
                fallbackSystemName: row.fallbackSystemName,
                showsSlash: false
            )
        case .on:
            return filledIconVisual
        case .off:
            return blockedIconVisual
        }
    }

    private var filledIconVisual: IconVisual {
        switch row.kind {
        case .sitePermission(let permissionType):
            return filledIconVisual(for: permissionType)
        case .popups:
            return IconVisual(iconName: "popup-fill", fallbackSystemName: "rectangle.on.rectangle.fill", showsSlash: false)
        case .externalScheme:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media-fill", fallbackSystemName: "play.rectangle.fill", showsSlash: false)
        case .externalApps:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus.fill", showsSlash: false)
        }
    }

    private func filledIconVisual(
        for permissionType: SumiPermissionType
    ) -> IconVisual {
        switch permissionType {
        case .camera:
            return IconVisual(iconName: "camera-fill", fallbackSystemName: "camera.fill", showsSlash: false)
        case .microphone:
            return IconVisual(iconName: "microphone-fill", fallbackSystemName: "mic.fill", showsSlash: false)
        case .cameraAndMicrophone:
            return IconVisual(iconName: "permissions-fill", fallbackSystemName: "video.fill", showsSlash: false)
        case .geolocation:
            return IconVisual(iconName: "location", fallbackSystemName: "location.fill", showsSlash: false)
        case .notifications:
            return IconVisual(iconName: nil, fallbackSystemName: "bell.fill", showsSlash: false)
        case .screenCapture:
            return IconVisual(iconName: "screen", fallbackSystemName: "display", showsSlash: false)
        case .popups:
            return IconVisual(iconName: "popup-fill", fallbackSystemName: "rectangle.on.rectangle.fill", showsSlash: false)
        case .externalScheme:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media-fill", fallbackSystemName: "play.rectangle.fill", showsSlash: false)
        case .storageAccess:
            return IconVisual(iconName: "cookies-fill", fallbackSystemName: "externaldrive.fill", showsSlash: false)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus.fill", showsSlash: false)
        }
    }

    private var blockedIconVisual: IconVisual {
        switch row.kind {
        case .sitePermission(let permissionType):
            return blockedIconVisual(for: permissionType)
        case .popups:
            return IconVisual(iconName: "popup", fallbackSystemName: "rectangle.on.rectangle", showsSlash: true)
        case .externalScheme:
            return IconVisual(iconName: "open", fallbackSystemName: "arrow.up.forward.square", showsSlash: true)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media", fallbackSystemName: "play.rectangle", showsSlash: true)
        case .externalApps:
            return IconVisual(iconName: "open", fallbackSystemName: "arrow.up.forward.square", showsSlash: true)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus", showsSlash: true)
        }
    }

    private func blockedIconVisual(
        for permissionType: SumiPermissionType
    ) -> IconVisual {
        switch permissionType {
        case .geolocation:
            return IconVisual(iconName: "location", fallbackSystemName: "location.fill", showsSlash: true)
        case .notifications:
            return IconVisual(iconName: "desktop-notification-blocked", fallbackSystemName: "bell.slash", showsSlash: false)
        case .screenCapture:
            return IconVisual(iconName: "screen-blocked", fallbackSystemName: "display", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media", fallbackSystemName: "play.rectangle", showsSlash: true)
        case .storageAccess:
            return IconVisual(iconName: "cookies-fill", fallbackSystemName: "externaldrive", showsSlash: true)
        default:
            return IconVisual(iconName: row.iconName, fallbackSystemName: row.fallbackSystemName, showsSlash: true)
        }
    }
}

struct HubSettingRow: View {
    let model: SiteControlsSettingRowModel
    let resetAction: (() -> Void)?
    let action: () -> Void

    @State private var isHovered = false

    init(
        model: SiteControlsSettingRowModel,
        resetAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.model = model
        self.resetAction = resetAction
        self.action = action
    }

    var body: some View {
        Group {
            if model.isInteractive && !model.isDisabled {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                rowContent
            }
        }
        .opacity(model.isDisabled ? 0.55 : 1)
        .contextMenu {
            if let resetAction {
                Button("Use Default", action: resetAction)
            }
        }
        .onHover { hovering in
            guard model.isInteractive && !model.isDisabled else {
                isHovered = false
                return
            }
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityIdentifier("urlhub-setting-row-\(model.id)")
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(capsuleFill)
                    .scaleEffect(capsuleScale)

                SumiZenChromeIcon(
                    iconName: model.chromeIconName,
                    fallbackSystemName: model.fallbackSystemName,
                    size: 16,
                    tint: URLBarHubNativeStyle.primaryText
                )
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    model.title,
                    font: .system(size: 13, weight: .medium),
                    color: URLBarHubNativeStyle.primaryText
                )
                if let subtitle = model.subtitle {
                    URLBarFadingText(
                        subtitle,
                        font: .system(size: 11.5),
                        color: URLBarHubNativeStyle.secondaryText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                    .frame(width: 14, height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var capsuleFill: Color {
        isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground
    }

    private var capsuleScale: CGFloat {
        isHovered ? 1.05 : 1
    }
}
