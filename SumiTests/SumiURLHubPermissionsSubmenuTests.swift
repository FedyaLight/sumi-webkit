import Combine
import XCTest

@testable import Sumi

final class SumiURLHubPermissionsSubmenuTests: XCTestCase {
    func testURLHubEmbedsPermissionsInlineWithoutSubmenuMode() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let models = try sourceFile("Sumi/Components/Sidebar/URLBarHubModels.swift")

        XCTAssertTrue(source.contains("Text(SumiCurrentSitePermissionsStrings.rowTitle)"))
        XCTAssertTrue(source.contains("URLHubPermissionInlineRow("))
        XCTAssertTrue(source.contains("permissionsInlineSection"))
        XCTAssertTrue(source.contains("currentSitePermissionsModel.rows"))
        XCTAssertFalse(source.contains("case permissions"))
        XCTAssertFalse(source.contains("SumiCurrentSitePermissionsView("))
        XCTAssertFalse(source.contains("kind: .permissions"))
        XCTAssertFalse(source.contains("URLBarHubInitialMode"))
        XCTAssertFalse(source.contains("modeRequestNonce"))
        XCTAssertFalse(source.contains("applyInitialMode"))
        XCTAssertTrue(models.contains("id: \"cookies\""))

        let cookiesRange = try XCTUnwrap(source.range(of: "ForEach(snapshot.settingsRows)"))
        let permissionsRange = try XCTUnwrap(source.range(of: "permissionsInlineSection"))
        XCTAssertLessThan(cookiesRange.lowerBound, permissionsRange.lowerBound)
    }

    func testURLHubPermissionsRowKeepsCookiesAndUnifiedProtectionRows() throws {
        let source = [
            try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift"),
            try sourceFile("Sumi/Components/Sidebar/URLBarHubModels.swift"),
        ].joined(separator: "\n")

        XCTAssertTrue(source.contains("kind: .cookies"))
        XCTAssertTrue(source.contains("kind: .protection("))
        XCTAssertTrue(source.contains("protectionCoordinator: browserManager.protectionCoordinator"))
        XCTAssertTrue(source.contains("protectionBrowserRestartRequired: browserManager.protectionCoordinator.settings.browserRestartRequired"))
        XCTAssertTrue(source.contains("protectionReloadRequired: currentTab?.isProtectionReloadRequired == true"))
        XCTAssertTrue(source.contains("case protectionDetails"))
        XCTAssertTrue(source.contains("setMode(.protectionDetails, direction: .forward)"))
        XCTAssertTrue(source.contains("setMode(.siteDataDetails, direction: .forward)"))
        XCTAssertFalse(source.contains("kind: .tracking("))
        XCTAssertFalse(source.contains("kind: .adBlocking("))
        XCTAssertFalse(source.contains("elementZap"))
        XCTAssertFalse(source.contains("startElementZap"))
        XCTAssertFalse(source.contains("boostsModule.startZapSelection"))
        XCTAssertFalse(source.contains("setMode(.permissions"))
    }

    func testProtectionRowShowsCurrentSiteStateAndDisclosure() {
        let row = SiteControlsSettingRowModel(
            id: "adblock-protection",
            chromeIconName: nil,
            fallbackSystemName: "shield.lefthalf.filled",
            title: "Adblock & Protection",
            subtitle: "Adblock on for this site",
            kind: .protection(
                plan: SumiProtectionRulePlan(
                    requestedLevel: .adblock,
                    effectiveLevel: .adblock,
                    siteHost: "example.com",
                    siteOverride: .inherit,
                    sitePolicyAllowsProtection: true,
                    activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
                    inactiveGroups: [],
                    bundleSource: nil,
                    nativeRuleBundleId: "bundle",
                    bundleProfileId: SumiProtectionBundleProfile.adblock,
                    requiredBundleProfileId: SumiProtectionBundleProfile.adblock,
                    activeGenerationId: "generation",
                    previousGenerationId: nil,
                    previousGenerationRetained: false,
                    ruleCountsByGroup: [:],
                    shardCountsByGroup: [:],
                    expectedRuleListIdentifiers: ["sumi.adblock.network.1"],
                    dedupeSummary: .empty,
                    overlapSummary: .deferred,
                    ineligibleSurfaceReason: nil,
                    planningErrors: [],
                    ruleDefinitions: []
                ),
                reloadRequired: false
            )
        )

        XCTAssertTrue(row.isInteractive)
        XCTAssertFalse(row.isDisabled)
        XCTAssertTrue(row.showsDisclosure)
    }

    func testProtectionDetailsUsesNativeRulesAndEyedropper() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarHubProtectionSection.swift")
        let zapperSource = try sourceFile("Sumi/ContentBlocking/SumiAdblockZapperStore.swift")

        XCTAssertTrue(source.contains("Image(systemName: \"eyedropper\")"))
        XCTAssertTrue(source.contains("SumiAdblockZapperStore.shared.state(forHost: host)"))
        XCTAssertTrue(source.contains("SumiAdblockZapperStore.shared.setRules("))
        XCTAssertTrue(source.contains("SumiAdblockZapperStore.shared.setEnabled("))
        XCTAssertTrue(source.contains("SumiAdblockZapperInjector.activateElementPicker("))
        XCTAssertTrue(zapperSource.contains("Sumi Element Zapper"))
        XCTAssertTrue(zapperSource.contains("data-sumi-zapper-selector"))
        XCTAssertTrue(zapperSource.contains("data-sumi-zapper-preview"))
        XCTAssertTrue(zapperSource.contains("data-sumi-zapper-create"))
        XCTAssertTrue(zapperSource.contains("restorePreview()"))
        XCTAssertTrue(zapperSource.contains("clearAppliedRules(to webView: WKWebView)"))
        XCTAssertTrue(zapperSource.contains("data-sumi-adblock-zapper-hidden"))
        XCTAssertTrue(source.contains("coordinator.setSiteOverride("))
        XCTAssertTrue(source.contains("if didActivate {\n                onClose()"))
        XCTAssertTrue(source.contains("Text(\"\\(savedRules.count) saved\")"))
        let popoverSource = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let lifecycleSource = try sourceFile("Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift")
        XCTAssertTrue(popoverSource.contains("currentTab?.markProtectionReloadRequiredIfNeeded("))
        XCTAssertTrue(lifecycleSource.contains("policy.isEnabled"))
        XCTAssertTrue(lifecycleSource.contains("SumiAdblockZapperInjector.clearAppliedRules(to: webView)"))
        XCTAssertFalse(source.contains("Image(systemName: \"scope\")"))
        XCTAssertFalse(source.contains("Timer"))
        XCTAssertFalse(source.contains(".onReceive("))
    }

    func testURLHubInlinePermissionsUseNonLiveSystemSnapshotModeAndIdentifiers() throws {
        let urlBar = try [
            sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarHubPermissionsSection.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarHubFooterSection.swift"),
        ].joined(separator: "\n")

        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlbar-site-controls-button\")"))
        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlhub-setting-row-\\(model.id)\")"))
        XCTAssertTrue(urlBar.contains("systemSnapshotMode: .none"))
        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlhub-permission-row-\\(row.id)\")"))
        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlhub-site-settings-button\")"))
    }

    func testCollapsedURLBarChromeActionsUseAppKitPrimaryRouting() throws {
        let urlBar = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")
        let trailingActions = try sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift")
        let permissionActions = try sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift")
        let zoomActions = try sourceFile("Sumi/Components/Sidebar/URLBarZoomPopover.swift")

        XCTAssertTrue(urlBar.contains(".sidebarAppKitPrimaryAction(action: focusFloatingBarFromURLBar)"))
        XCTAssertTrue(trailingActions.contains(".sidebarAppKitPrimaryAction(isEnabled: isAvailable, action: action)"))
        XCTAssertTrue(trailingActions.contains(".sidebarAppKitPrimaryAction(action: action)"))
        XCTAssertTrue(permissionActions.contains(".sidebarAppKitPrimaryAction(action: action)"))
        XCTAssertTrue(zoomActions.contains(".sidebarAppKitPrimaryAction(action: action)"))
    }

    func testURLBarFocusTapTargetExcludesTrailingHubButton() throws {
        let urlBar = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")
        let leadingContentRange = try XCTUnwrap(urlBar.range(of: "leadingContent"))
        let focusTapRange = try XCTUnwrap(urlBar.range(of: ".onTapGesture(perform: focusFloatingBarFromURLBar)"))
        let trailingActionsRange = try XCTUnwrap(urlBar.range(of: "trailingActions(for: currentTab)"))

        XCTAssertLessThan(leadingContentRange.lowerBound, focusTapRange.lowerBound)
        XCTAssertLessThan(focusTapRange.lowerBound, trailingActionsRange.lowerBound)
        XCTAssertTrue(urlBar.contains("func focusFloatingBarFromURLBar()"))
        XCTAssertFalse(urlBar.contains("guard !isZoomButtonHovering else { return }"))
    }

    func testURLHubUsesNativeAdaptivePopoverHostAndTheming() throws {
        let trailingActions = try sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift")
        let popover = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let bookmarkEditor = try sourceFile("Sumi/Components/Sidebar/URLBarBookmarkEditorView.swift")
        let nativeStyle = try sourceFile("Sumi/Components/Sidebar/URLBarHubNativeStyle.swift")
        let extensionActions = try sourceFile("Sumi/Components/Extensions/ExtensionActionView.swift")
        let presenter = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopoverPresenter.swift")
        let material = try sourceFile("Sumi/Theme/NativeChromeMaterialBackground.swift")

        XCTAssertTrue(trailingActions.contains("URLBarHubPopoverAnchorView("))
        XCTAssertFalse(trailingActions.contains(".popover(isPresented: $isHubPresented"))
        XCTAssertTrue(presenter.contains("NSPopover()"))
        XCTAssertTrue(presenter.contains("popover.appearance = popoverAppearance(for: registration)"))
        XCTAssertTrue(presenter.contains("registration.themeContext.nativeSurfaceColorScheme"))
        XCTAssertTrue(popover.contains("NativeChromeMaterialBackground(role: .popover)"))
        XCTAssertTrue(popover.contains("URLBarHubNativeStyle.backgroundFallback"))
        XCTAssertTrue(bookmarkEditor.contains(".textFieldStyle(.roundedBorder)"))
        XCTAssertTrue(nativeStyle.contains("Color(nsColor: .labelColor)"))
        XCTAssertTrue(nativeStyle.contains("Color(nsColor: .controlBackgroundColor)"))
        XCTAssertTrue(material.contains("case popover"))
        XCTAssertTrue(material.contains("return .popover"))
        XCTAssertFalse(popover.contains("ChromeThemeTokens"))
        XCTAssertFalse(popover.contains("tokens."))
        XCTAssertFalse(popover.contains("ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors"))
        XCTAssertFalse(bookmarkEditor.contains("ChromeThemeTokens"))
        XCTAssertFalse(bookmarkEditor.contains("tokens."))
        XCTAssertFalse(bookmarkEditor.contains("floatingBarBackground"))
        XCTAssertFalse(extensionActions.contains("ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors"))
        XCTAssertFalse(presenter.contains("Timer"))
        XCTAssertFalse(presenter.contains("NotificationCenter.default.addObserver"))
        XCTAssertFalse(presenter.contains("modeRequestNonce"))
        XCTAssertFalse(presenter.contains("URLBarHubInitialMode"))
    }

    func testURLHubPermissionRowsUseClickCycleAndContextMenu() throws {
        let popover = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let permissionsSection = try sourceFile("Sumi/Components/Sidebar/URLBarHubPermissionsSection.swift")

        XCTAssertTrue(popover.contains("cyclePermission(row)"))
        XCTAssertTrue(popover.contains("nextInlineOption("))
        XCTAssertTrue(permissionsSection.contains(".contextMenu"))
        XCTAssertTrue(permissionsSection.contains("onSelect(option)"))
        XCTAssertTrue(permissionsSection.contains("filledIconVisual"))
        XCTAssertTrue(permissionsSection.contains("blockedIconVisual"))
        XCTAssertTrue(permissionsSection.contains("showsSlash"))
        XCTAssertFalse(permissionsSection.contains("inlineStateTitle"))
        XCTAssertFalse(popover.contains("proposed = .default"))
        XCTAssertFalse(popover.contains("proposed = .ask"))
    }

    func testURLHubPermissionIconsUseSingleSlashAndStableLocationGlyph() throws {
        let permissionsSection = try sourceFile("Sumi/Components/Sidebar/URLBarHubPermissionsSection.swift")

        XCTAssertTrue(permissionsSection.contains("return IconVisual(iconName: \"autoplay-media\", fallbackSystemName: \"play.rectangle\", showsSlash: true)"))
        XCTAssertFalse(permissionsSection.contains("IconVisual(iconName: \"autoplay-media-blocked\", fallbackSystemName: \"play.rectangle\", showsSlash: true)"))
        XCTAssertTrue(permissionsSection.contains("return IconVisual(iconName: \"location\", fallbackSystemName: \"location.fill\", showsSlash: false)"))
        XCTAssertTrue(permissionsSection.contains("return IconVisual(iconName: \"location\", fallbackSystemName: \"location.fill\", showsSlash: true)"))
        XCTAssertFalse(permissionsSection.contains("location-solid"))
    }

    func testURLHubFooterUsesGearMenuForSiteActions() throws {
        let popover = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let footerSection = try sourceFile("Sumi/Components/Sidebar/URLBarHubFooterSection.swift")
        let source = [popover, footerSection].joined(separator: "\n")

        XCTAssertFalse(source.contains("actionTitle: \"More\""))
        XCTAssertFalse(source.contains("fallbackSystemName: \"ellipsis\""))
        XCTAssertFalse(source.contains("iconName: \"menu\""))
        XCTAssertTrue(footerSection.contains("Image(systemName: \"gearshape\")"))
        XCTAssertTrue(footerSection.contains(".lineLimit(1)"))
        XCTAssertTrue(footerSection.contains(".minimumScaleFactor(0.86)"))
        XCTAssertTrue(popover.contains("siteSettingsAction: openSiteSettings"))
        XCTAssertTrue(popover.contains("clearSiteDataAction: openSiteDataDetails"))
        XCTAssertTrue(popover.contains("resetPermissionsAction: resetPermissionsToDefault"))
        XCTAssertTrue(footerSection.contains("Button(\"Site Settings\", action: siteSettingsAction)"))
        XCTAssertTrue(footerSection.contains("Button(\"Clear Site Data\", action: clearSiteDataAction)"))
        XCTAssertTrue(footerSection.contains("Button(\"Reset Permissions to Default\", action: resetPermissionsAction)"))
    }

    func testURLHubPermissionRowsUseCompactPolicySubtitles() throws {
        let rowsBuilder = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionRowsBuilder.swift")

        XCTAssertTrue(rowsBuilder.contains("compactPolicySubtitle("))
        XCTAssertTrue(rowsBuilder.contains("SumiCurrentSitePermissionsStrings.policyOn"))
        XCTAssertTrue(rowsBuilder.contains("SumiCurrentSitePermissionsStrings.policyOff"))
        XCTAssertFalse(rowsBuilder.contains("Used by this site"))
        XCTAssertFalse(rowsBuilder.contains("Requested by this site"))
        XCTAssertFalse(rowsBuilder.contains("Saved setting on this site"))
    }

    func testPermissionIndicatorIsHiddenWhileURLHubIsPresented() throws {
        let permissionActions = try sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift")
        let presenter = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopoverPresenter.swift")

        XCTAssertTrue(presenter.contains("func isPresented(in windowState: BrowserWindowState) -> Bool"))
        XCTAssertTrue(permissionActions.contains("urlBarHubPopoverPresenter.isPresented(in: windowState)"))
        XCTAssertTrue(permissionActions.contains("return .hidden"))
    }

    func testTopLevelAutoplayControlWasMovedOutOfSiteControlsRows() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertFalse(source.contains("kind: .autoplay("))
        XCTAssertFalse(source.contains("id: \"autoplay\",\n                        chromeIconName"))
    }

    func testInlinePermissionsDoNotUseForbiddenAPIs() throws {
        let hub = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let viewModel = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsViewModel.swift")
        let rowsBuilder = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionRowsBuilder.swift")
        let permissionsUI = [viewModel, rowsBuilder].joined(separator: "\n")

        XCTAssertFalse(hub.contains("SwiftData"))
        XCTAssertFalse(hub.contains("requestAuthorization"))
        XCTAssertFalse(permissionsUI.contains("requestAuthorization"))
        XCTAssertFalse(hub.contains("WKPermissionDecision"))
        XCTAssertFalse(permissionsUI.contains("WKPermissionDecision"))
        XCTAssertFalse(permissionsUI.contains("UserDefaults"))
    }

    func testURLHubInlinePermissionsCoalesceStoreDrivenReloads() throws {
        let view = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(view.contains("@State private var scheduledPermissionsReloadTask"))
        XCTAssertTrue(view.contains("schedulePermissionsReloadAfterStoreChange()"))
        XCTAssertTrue(view.contains("scheduledPermissionsReloadTask?.cancel()"))
    }

    func testURLHubUsesDynamicHeightAndFilteredRows() throws {
        let view = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopover.swift")
        let rowsBuilder = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionRowsBuilder.swift")

        XCTAssertTrue(view.contains("URLBarHubPopoverContentSizePreferenceKey"))
        XCTAssertTrue(view.contains("onContentSizeChange(size)"))
        XCTAssertTrue(view.contains("!snapshot.settingsRows.isEmpty || !currentSitePermissionsModel.rows.isEmpty"))
        XCTAssertTrue(rowsBuilder.contains("appendSitePermissionRowIfRelevant("))
        XCTAssertTrue(rowsBuilder.contains("shouldShowSitePermissionRow("))
        XCTAssertTrue(rowsBuilder.contains("recentEventCount > 0 || runtimeStatus != nil || siteActivity != nil"))
        XCTAssertTrue(rowsBuilder.contains("hasResolvedDecision(for: key)"))
    }

    @MainActor
    func testPermissionEventSnapshotReadsDoNotPublishChanges() {
        let store = SumiPermissionIndicatorEventStore()
        let now = Date()
        store.record(
            SumiPermissionIndicatorEventRecord(
                id: "expired-notification",
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com",
                permissionTypes: [.notifications],
                category: .blockedEvent,
                visualStyle: .blocked,
                priority: .blockedNotification,
                createdAt: now.addingTimeInterval(-20),
                expiresAt: now.addingTimeInterval(-10)
            )
        )

        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }

        XCTAssertTrue(store.recordsSnapshot(forPageId: "tab-a:1", now: now).isEmpty)
        XCTAssertEqual(changeCount, 0)
        cancellable.cancel()
    }

    func testDocumentationRecordsNoDDGImplementationCopy() throws {
        let licenseNotes = try sourceFile("docs/permissions/LICENSE_NOTES.md")
        let lowercasedNotes = licenseNotes.lowercased()

        XCTAssertTrue(licenseNotes.contains("DDG Permission Center"))
        XCTAssertTrue(
            lowercasedNotes.contains("no implementation source was copied")
                || lowercasedNotes.contains("no duckduckgo swiftui/appkit view source, implementation source")
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let testsURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
