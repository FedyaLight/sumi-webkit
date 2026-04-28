import SwiftUI

struct SumiCurrentSitePermissionsView: View {
    @ObservedObject var model: SumiCurrentSitePermissionsViewModel

    let currentTab: Tab?
    let profile: Profile?
    let permissionCoordinator: any SumiPermissionCoordinating
    let runtimePermissionController: any SumiRuntimePermissionControlling
    let systemPermissionService: any SumiSystemPermissionService
    let blockedPopupStore: SumiBlockedPopupStore
    let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
    let onBack: () -> Void
    let onClose: () -> Void
    let onOpenSiteSettings: () -> Void
    let onDidMutate: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var runtimeControlsModel = SumiPermissionRuntimeControlsViewModel()
    @State private var scheduledReloadTask: Task<Void, Never>?

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var dependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: permissionCoordinator,
            systemPermissionService: systemPermissionService,
            runtimeController: runtimePermissionController,
            autoplayStore: SumiAutoplayPolicyStoreAdapter.shared,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore,
            indicatorEventStore: permissionIndicatorEventStore
        )
    }

    private var displayDomain: String {
        model.context?.displayDomain ?? currentTab?.url.host ?? "This site"
    }

    private var loadKey: String {
        [
            profile?.id.uuidString ?? "none",
            profile?.isEphemeral == true ? "ephemeral" : "persistent",
            currentTab?.id.uuidString ?? "none",
            currentTab?.currentPermissionPageId() ?? "none",
            currentTab?.url.absoluteString ?? "none",
            currentTab?.isAutoplayReloadRequired == true ? "autoplay-reload" : "autoplay-ready",
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            content

            Divider()
                .padding(.horizontal, 8)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .accessibilityIdentifier("urlhub-permissions-submenu")
        .task(id: loadKey) {
            await reloadImmediately()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            guard let tab = notification.object as? Tab,
                  tab.id == currentTab?.id
            else { return }
            scheduleReloadAfterStoreChange()
        }
        .onReceive(blockedPopupStore.objectWillChange) { _ in
            scheduleReloadAfterStoreChange()
        }
        .onReceive(externalSchemeSessionStore.objectWillChange) { _ in
            scheduleReloadAfterStoreChange()
        }
        .onReceive(permissionIndicatorEventStore.objectWillChange) { _ in
            scheduleReloadAfterStoreChange()
        }
        .onDisappear {
            scheduledReloadTask?.cancel()
            scheduledReloadTask = nil
            runtimeControlsModel.clear()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SumiCurrentSitePermissionIconButton(
                systemName: "chevron.left",
                help: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(SumiCurrentSitePermissionsStrings.headerTitlePrefix) \(displayDomain)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                Text(model.context?.origin.identity ?? displayDomain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SumiCurrentSitePermissionIconButton(
                systemName: "xmark",
                help: "Close",
                action: onClose
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.context?.isSupportedWebOrigin != true {
            unavailableState
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let activityText = model.summary.activityText {
                        Text(activityText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(tokens.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if model.isLoading && model.rows.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading permissions...")
                                .font(.system(size: 12.5))
                                .foregroundStyle(tokens.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                    } else {
                        if runtimeControlsModel.hasVisibleContent {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(SumiPermissionRuntimeControlsStrings.sectionTitle)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.secondaryText)
                                    .textCase(.uppercase)
                                    .tracking(0.4)

                                SumiPermissionRuntimeControlsView(
                                    model: runtimeControlsModel,
                                    onAction: { actionKind in
                                        await performRuntimeAction(actionKind)
                                    }
                                )
                            }
                        }

                        VStack(spacing: 6) {
                            ForEach(model.rows) { row in
                                SumiCurrentSitePermissionRowView(
                                    row: row,
                                    onSelect: { option in
                                        Task { await select(option, for: row) }
                                    },
                                    onOpenSystemSettings: {
                                        Task {
                                            await model.openSystemSettings(
                                                for: row,
                                                systemPermissionService: systemPermissionService
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if let statusMessage = model.statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.secondaryText)
                    }
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxHeight: 520)
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SumiCurrentSitePermissionsStrings.unavailableTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
            Text(SumiCurrentSitePermissionsStrings.unavailableSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(tokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.resetCurrentSite(
                        profile: profile,
                        dependencies: dependencies
                    )
                    await reloadImmediately()
                    onDidMutate()
                }
            } label: {
                if model.isResetting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(SumiCurrentSitePermissionsStrings.resetTitle)
                }
            }
            .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 154))
            .disabled(model.context?.isSupportedWebOrigin != true || model.isResetting)

            Spacer(minLength: 0)

            Button(SumiCurrentSitePermissionsStrings.siteSettingsTitle) {
                onOpenSiteSettings()
            }
            .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 104))
        }
    }

    private func select(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiCurrentSitePermissionRow
    ) async {
        await model.select(
            option,
            for: row,
            profile: profile,
            dependencies: dependencies,
            onAutoplayChanged: {
                currentTab?.markAutoplayReloadRequiredIfNeeded(
                    afterChangingPolicyFor: currentTab?.url
                )
                currentTab?.updateAutoplayReloadRequirementForCurrentSite()
            }
        )
        await reloadImmediately()
        onDidMutate()
    }

    private func reloadImmediately() async {
        scheduledReloadTask?.cancel()
        scheduledReloadTask = nil
        await reload()
    }

    private func scheduleReloadAfterStoreChange() {
        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await reload()
            scheduledReloadTask = nil
        }
    }

    private func reload() async {
        await model.load(
            tab: currentTab,
            profile: profile,
            dependencies: dependencies,
            systemSnapshotMode: .none
        )
        configureRuntimeControls()
    }

    private func configureRuntimeControls() {
        runtimeControlsModel.load(
            pageContext: runtimeControlsPageContext(),
            runtimeController: runtimePermissionController,
            reloadRequired: currentTab?.isAutoplayReloadRequired == true,
            onRuntimeStateChanged: {
                scheduleReloadAfterStoreChange()
            }
        )
    }

    private func performRuntimeAction(
        _ actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) async {
        _ = await runtimeControlsModel.perform(actionKind)
        await reloadImmediately()
        onDidMutate()
    }

    private func runtimeControlsPageContext() -> SumiPermissionRuntimeControlsViewModel.PageContext? {
        guard let context = model.context,
              context.isSupportedWebOrigin
        else { return nil }

        let tab = currentTab
        return SumiPermissionRuntimeControlsViewModel.PageContext(
            tabId: context.tabId,
            pageId: context.pageId,
            navigationOrPageGeneration: context.navigationOrPageGeneration,
            displayDomain: context.displayDomain,
            currentWebView: { [weak tab] in
                tab?.existingWebView
            },
            isCurrentPage: { [weak tab] tabId, pageId, navigationOrPageGeneration in
                guard let tab else { return false }
                return tab.id.uuidString.lowercased() == tabId
                    && tab.currentPermissionPageId() == pageId
                    && String(tab.extensionRuntimeDocumentSequence) == navigationOrPageGeneration
            },
            reloadPage: { [weak tab] in
                guard let tab,
                      tab.existingWebView != nil
                else { return false }
                tab.refresh()
                tab.updateAutoplayReloadRequirementForCurrentSite()
                return true
            },
            isGeolocationStillAllowed: {
                let decision = await permissionCoordinator.queryPermissionState(
                    context.securityContext(for: .geolocation)
                )
                return decision.outcome == .granted || decision.state == .allow
            },
            clearGeolocationGrantForVisit: {
                await permissionCoordinator.resetTransientDecisions(
                    profilePartitionId: context.profilePartitionId,
                    pageId: context.pageId,
                    requestingOrigin: context.origin,
                    topOrigin: context.origin,
                    reason: "runtime-stop-geolocation-this-visit"
                )
            }
        )
    }
}

private struct SumiCurrentSitePermissionRowView: View {
    let row: SumiCurrentSitePermissionRow
    let onSelect: (SumiCurrentSitePermissionOption) -> Void
    let onOpenSystemSettings: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if row.isEditable {
                        optionMenu
                    }
                }

                ForEach(Array(row.statusLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(statusColor(for: line))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if row.showsSystemSettingsAction {
                    Button("Open System Settings", action: onOpenSystemSettings)
                        .font(.system(size: 11.5, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(tokens.primaryText)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(row.disabledReason == nil ? 1 : 0.62)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("urlhub-permission-row-\(row.id)")
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.commandPaletteBackground.opacity(0.8))

            SumiZenChromeIcon(
                iconName: row.iconName,
                fallbackSystemName: row.fallbackSystemName,
                size: 16,
                tint: tokens.primaryText
            )
        }
        .frame(width: 34, height: 34)
    }

    private var optionMenu: some View {
        Menu {
            ForEach(row.availableOptions) { option in
                Button(option.title) {
                    onSelect(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(row.currentOption?.shortTitle ?? "Info")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(tokens.commandPaletteBackground.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(row.availableOptions.isEmpty)
    }

    private func statusColor(for line: String) -> Color {
        if line.localizedCaseInsensitiveContains("blocked")
            || line.localizedCaseInsensitiveContains("denied")
            || line.localizedCaseInsensitiveContains("disabled")
            || line.localizedCaseInsensitiveContains("restricted")
            || line.localizedCaseInsensitiveContains("requires")
        {
            return Color.red.opacity(0.85)
        }
        if line.localizedCaseInsensitiveContains("active")
            || line.localizedCaseInsensitiveContains("allow")
        {
            return tokens.primaryText.opacity(0.85)
        }
        return tokens.secondaryText
    }
}

private struct SumiCurrentSitePermissionIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .frame(width: 28, height: 28)
                .background(isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
