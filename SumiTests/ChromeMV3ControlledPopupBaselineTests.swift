import AppKit
import Foundation
import SwiftData
import XCTest
#if canImport(WebKit)
import WebKit
#endif

@testable import Sumi

final class ChromeMV3ControlledPopupBaselineTests: XCTestCase {
    private let mv3TestExtensionsRoot = URL(
        fileURLWithPath:
            "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions",
        isDirectory: true
    )
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testControlledPopupBaselineMatrix() async throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup baseline matrix requires macOS 15.5.")
        }

        var rows: [ChromeMV3ControlledPopupBaselineMatrixRow] = []

        for fixtureID in ChromeMV3ControlledPopupBaselineFixtureID.allCases {
            rows.append(try await evaluateMinimalFixtureRow(fixtureID: fixtureID))
        }

        rows.append(try await evaluateBitwardenExtensionRow())
        rows.append(raindropReferenceRow())
        rows.append(try await evaluateProtonPassExtensionRow())
        rows.append(try await evaluateOnePasswordPreflightRow())
        rows.append(try await evaluateSumiUsablePopupExtensionRow())

        for row in rows {
            print(
                "SumiControlledPopupBaseline row=\(row.rowID) layer=\(row.layer.rawValue) outcome=\(row.outcome.rawValue) ranLivePopup=\(row.ranLivePopup) notes=\(row.notes)"
            )
        }

        attachMatrix(rows)

        let staticRow = rows.first {
            $0.rowID
                == ChromeMV3ControlledPopupBaselineFixtureID.minimalStatic
                .rawValue
        }
        XCTAssertEqual(staticRow?.outcome, .usableUI)
        XCTAssertTrue(staticRow?.ranLivePopup == true)

        let tabsSendMessageRow = rows.first {
            $0.rowID
                == ChromeMV3ControlledPopupBaselineFixtureID.minimalTabsSendMessage
                .rawValue
        }
        XCTAssertEqual(
            tabsSendMessageRow?.outcome,
            .usableUI,
            "minimal-tabs-sendMessage must reach usableUI through the generic popup/content-script path."
        )

        let bitwardenRow = rows.first {
            $0.rowID == ChromeMV3ControlledPopupBaselineExtensionID.bitwarden.rawValue
        }
        if let bitwardenRow, bitwardenRow.ranLivePopup {
            XCTAssertTrue(
                bitwardenRow.outcome == .usableUI
                    || bitwardenRow.outcome == .extensionLocalAppState,
                "Bitwarden controlled popup baseline should reach usable UI or remain extension-local app-state wait. outcome=\(bitwardenRow.outcome.rawValue)"
            )
        }

        XCTAssertEqual(
            rows.first {
                $0.rowID
                    == ChromeMV3ControlledPopupBaselineExtensionID
                    .raindropReference.rawValue
            }?.outcome,
            .extensionLocalRenderState
        )

        let onePasswordRow = rows.first {
            $0.rowID
                == ChromeMV3ControlledPopupBaselineExtensionID.onePassword.rawValue
        }
        if let onePasswordRow, onePasswordRow.ranLivePopup == false {
            XCTAssertEqual(onePasswordRow.outcome, .moduleWorkerUnsupported)
        }

        let sumiUsablePopupRow = rows.first {
            $0.rowID
                == ChromeMV3ControlledPopupBaselineExtensionID.sumiUsablePopup
                .rawValue
        }
        if let sumiUsablePopupRow, sumiUsablePopupRow.ranLivePopup {
            XCTAssertEqual(
                sumiUsablePopupRow.outcome,
                .usableUI,
                "Real-package usable popup fixture should reach usableUI through the local unpacked flow."
            )
        }

        if let firstGenericFailure = firstFailingMinimalFixtureLayer(in: rows) {
            print(
                "SumiControlledPopupBaseline firstFailingGenericLayer=\(firstGenericFailure.fixtureID.rawValue) outcome=\(firstGenericFailure.outcome.rawValue)"
            )
            if firstGenericFailure.fixtureID != .minimalStatic {
                XCTAssertEqual(
                    rows.first {
                        $0.rowID
                            == ChromeMV3ControlledPopupBaselineFixtureID
                            .minimalStatic.rawValue
                    }?.outcome,
                    .usableUI,
                    "Minimal static popup must pass before later generic layers are triaged."
                )
            }
        }
    }

    @MainActor
    func testMinimalTabsSendMessageBindRegistersListener() async throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup baseline matrix requires macOS 15.5.")
        }
        let context = try makeLiveTabModuleFixture(
            profileName: "Baseline Tabs SendMessage Bind"
        )
        defer { context.tearDown() }
        context.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed =
            true
        _ = try XCTUnwrap(
            context.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        windowRegistry.register(windowState)
        context.browserManager.windowRegistry = windowRegistry
        context.browserManager.webViewCoordinator = WebViewCoordinator()
        let root = try makeTemporaryDirectory()
        let fixtureID = ChromeMV3ControlledPopupBaselineFixtureID.minimalTabsSendMessage
        let source = try makeFixtureDirectory(
            named: "baseline-\(fixtureID.rawValue)-bind",
            manifest: ChromeMV3ControlledPopupBaselineFixtureFactory.manifest(
                for: fixtureID
            ),
            files: ChromeMV3ControlledPopupBaselineFixtureFactory.files(
                for: fixtureID
            )
        )
        let install = context.module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: context.profile.id.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: context.module,
            extensionId: record.extensionID
        )
        let tab = context.makeTab(
            url: URL(string: "https://example.com/article")!
        )
        tab.primaryWindowId = windowState.id
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.baseline.tabsSendMessage.bind")
        )
        tab._webView = webView
        try XCTUnwrap(context.browserManager.webViewCoordinator).setWebView(
            webView,
            for: tab.id,
            in: windowState.id
        )
        let navigationObserver = BaselineMaterializedTabNavigationObserver()
        webView.navigationDelegate = navigationObserver
        let navigation = webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Baseline Materialized Tab</title></head>
              <body><main><h1>Fixture</h1></main></body>
            </html>
            """,
            baseURL: tab.url
        )
        try await navigationObserver.wait(navigation: navigation)
        context.module.noteChromeMV3ContentScriptLifecycleEntrypointIfLoaded(
            tab,
            webView: webView,
            url: tab.url,
            entrypoint: .initialPageLoadEligibility,
            reason: "baseline.fixture.tabsSendMessage.bind"
        )
        let manager = try XCTUnwrap(context.module.managerIfEnabled())
        _ = await manager
            .bindChromeMV3ScriptingExecuteScriptTargetForURLHubActionClickIfAllowed(
                currentTab: tab,
                localExperimentalGateAllowed: true
            )
        let registry = manager.chromeMV3ContentScriptEndpointRegistryIfLoaded()
        let contentWorld = WKContentWorld.world(
            name: "sumi.mv3.content.\(record.profileID).\(record.extensionID)"
        )
        let pageReadyState = try await webView.callAsyncJavaScript(
            "return document.readyState",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let listenerCount = try await webView.callAsyncJavaScript(
            """
            return (typeof chrome !== "undefined"
              && chrome.runtime
              && chrome.runtime.onMessage
              && typeof chrome.runtime.onMessage.listenerCount === "function")
              ? chrome.runtime.onMessage.listenerCount()
              : 0;
            """,
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        )
        let summary = [
            "pageReadyState=\(String(describing: pageReadyState ?? "nil"))",
            "jsListenerCount=\(String(describing: listenerCount ?? "nil"))",
            "nativeListenerEndpoints=\(registry?.summary.messageListenerEndpointCount ?? -1)",
        ].joined(separator: " | ")
        XCTAssertGreaterThan(
            registry?.summary.messageListenerEndpointCount ?? 0,
            0,
            summary
        )
    }

    @MainActor
    func testControlledPopupBaselineDisabledModuleRemainsZeroCost() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeFixtureDirectory(
            named: "baseline-disabled-module",
            manifest: ChromeMV3ControlledPopupBaselineFixtureFactory.manifest(
                for: .minimalStatic
            ),
            files: ChromeMV3ControlledPopupBaselineFixtureFactory.files(
                for: .minimalStatic
            )
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-baseline-disabled",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        module.setEnabled(false)

        let section = module.chromeMV3URLHubSectionViewModelIfEnabled(
            rootURL: root,
            currentPage: syntheticPageContext(profileID: record.profileID),
            now: Date(timeIntervalSince1970: 1_720_100_000)
        )

        XCTAssertNil(section)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    // MARK: - Minimal fixtures

    @MainActor
    private func evaluateMinimalFixtureRow(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) async throws -> ChromeMV3ControlledPopupBaselineMatrixRow {
        if ChromeMV3ControlledPopupBaselineFixtureFactory.requiresMaterializedTab(
            fixtureID
        ) {
            return try await evaluateMaterializedTabFixtureRow(
                fixtureID: fixtureID
            )
        }
        return try await evaluateSimpleFixtureRow(fixtureID: fixtureID)
    }

    @MainActor
    private func evaluateSimpleFixtureRow(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) async throws -> ChromeMV3ControlledPopupBaselineMatrixRow {
        let root = try makeTemporaryDirectory()
        let source = try makeFixtureDirectory(
            named: "baseline-\(fixtureID.rawValue)",
            manifest: ChromeMV3ControlledPopupBaselineFixtureFactory.manifest(
                for: fixtureID
            ),
            files: ChromeMV3ControlledPopupBaselineFixtureFactory.files(
                for: fixtureID
            )
        )
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        let evaluation = try await evaluateOpenedPopupFixture(
            fixtureID: fixtureID,
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID,
            opened: result.opened,
            preflightBlocker: result.blocker,
            notes: result.opened
                ? "controlledCompatibilityActionPopup"
                : (result.blocker?.rawValue ?? "blocked")
        )
        return evaluation
    }

    @MainActor
    private func evaluateMaterializedTabFixtureRow(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID
    ) async throws -> ChromeMV3ControlledPopupBaselineMatrixRow {
        let context = try makeLiveTabModuleFixture(
            profileName: "Baseline Materialized Tab"
        )
        defer { context.tearDown() }
        context.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed =
            true
        _ = try XCTUnwrap(
            context.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        windowRegistry.register(windowState)
        context.browserManager.windowRegistry = windowRegistry
        context.browserManager.webViewCoordinator = WebViewCoordinator()

        let root = try makeTemporaryDirectory()
        let source = try makeFixtureDirectory(
            named: "baseline-\(fixtureID.rawValue)",
            manifest: ChromeMV3ControlledPopupBaselineFixtureFactory.manifest(
                for: fixtureID
            ),
            files: ChromeMV3ControlledPopupBaselineFixtureFactory.files(
                for: fixtureID
            )
        )
        let install = context.module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: context.profile.id.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: context.module,
            extensionId: record.extensionID
        )
        _ = context.module.managerIfEnabled()?.loadInstalledExtensionMetadata()

        let manager = try XCTUnwrap(context.module.managerIfEnabled())
        let tab = context.makeTab(
            url: URL(string: "https://example.com/article")!
        )
        tab.primaryWindowId = windowState.id
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.baseline.materializedTab")
        )
        tab._webView = webView
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            throw XCTSkip(
                "Materialized WebView did not receive the normal-tab configuration marker."
            )
        }
        try XCTUnwrap(context.browserManager.webViewCoordinator).setWebView(
            webView,
            for: tab.id,
            in: windowState.id
        )

        let navigationObserver = BaselineMaterializedTabNavigationObserver()
        webView.navigationDelegate = navigationObserver
        let navigation = webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Baseline Materialized Tab</title></head>
              <body><main><h1>Fixture</h1></main></body>
            </html>
            """,
            baseURL: tab.url
        )
        try await navigationObserver.wait(navigation: navigation)

        context.module.noteChromeMV3ContentScriptLifecycleEntrypointIfLoaded(
            tab,
            webView: webView,
            url: tab.url,
            entrypoint: .initialPageLoadEligibility,
            reason: "baseline.fixture.contentScriptAttach"
        )
        let result = await context.module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: tab
        )

        defer {
            _ = context.module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        if result.opened {
            _ = manager.chromeMV3ScriptingExecuteScriptLocalTabIDIfLoaded(
                for: tab.id
            )
        }

        return try await evaluateOpenedPopupFixture(
            fixtureID: fixtureID,
            module: context.module,
            profileID: record.profileID,
            extensionID: record.extensionID,
            opened: result.opened,
            preflightBlocker: result.blocker,
            notes: result.opened
                ? "materializedTab controlledCompatibilityActionPopup"
                : (result.blocker?.rawValue ?? "blocked")
        )
    }

    @MainActor
    private func evaluateOpenedPopupFixture(
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID,
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String,
        opened: Bool,
        preflightBlocker: BrowserExtensionActionPopupBlocker?,
        notes: String
    ) async throws -> ChromeMV3ControlledPopupBaselineMatrixRow {
        var domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
        var snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        if opened {
            snapshot = try await waitForPopupBridgeSnapshot(
                module: module,
                profileID: profileID,
                extensionID: extensionID
            )
            domProbe = try await waitForBaselineDOMProbe(
                module: module,
                profileID: profileID,
                extensionID: extensionID
            )
        }

        let outcome = ChromeMV3ControlledPopupBaselineClassifier
            .classifyMinimalFixture(
                fixtureID: fixtureID,
                opened: opened,
                preflightBlocker: preflightBlocker,
                domProbe: domProbe,
                snapshot: snapshot
            )

        return ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: fixtureID.rawValue,
            layer: ChromeMV3ControlledPopupBaselineFixtureFactory.layer(
                for: fixtureID
            ),
            outcome: outcome,
            ranLivePopup: opened,
            notes: notes
        )
    }

    // MARK: - Real extensions

    @MainActor
    private func evaluateBitwardenExtensionRow() async throws
        -> ChromeMV3ControlledPopupBaselineMatrixRow
    {
        let packageRoot = mv3TestExtensionsRoot.appendingPathComponent(
            "bitwarden",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            return ChromeMV3ControlledPopupBaselineMatrixRow(
                rowID: ChromeMV3ControlledPopupBaselineExtensionID.bitwarden
                    .rawValue,
                layer: .realExtensionAppSpecific,
                outcome: .unknown,
                ranLivePopup: false,
                notes: "packageUnavailable"
            )
        }

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        var snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        var domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
        if result.opened {
            snapshot = try await waitForPopupBridgeSnapshot(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
            domProbe = try await waitForRealExtensionPopupDOMProbe(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        let outcome = ChromeMV3ControlledPopupBaselineClassifier.classifyBitwarden(
            opened: result.opened,
            snapshot: snapshot,
            domProbe: domProbe
        )

        return ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: ChromeMV3ControlledPopupBaselineExtensionID.bitwarden.rawValue,
            layer: .realExtensionAppSpecific,
            outcome: outcome,
            ranLivePopup: result.opened,
            notes: "appStateDependencyTrace no product support claim"
        )
    }

    private func raindropReferenceRow()
        -> ChromeMV3ControlledPopupBaselineMatrixRow
    {
        ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: ChromeMV3ControlledPopupBaselineExtensionID.raindropReference
                .rawValue,
            layer: .realExtensionAppSpecific,
            outcome: .extensionLocalRenderState,
            ranLivePopup: false,
            notes:
                "closeRaindropAsExtensionLocalRenderState reference only; deep diagnostics closed"
        )
    }

    @MainActor
    private func evaluateProtonPassExtensionRow() async throws
        -> ChromeMV3ControlledPopupBaselineMatrixRow
    {
        let packageRoot = mv3TestExtensionsRoot.appendingPathComponent(
            "Proton",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            return ChromeMV3ControlledPopupBaselineMatrixRow(
                rowID: ChromeMV3ControlledPopupBaselineExtensionID.protonPass
                    .rawValue,
                layer: .realExtensionAppSpecific,
                outcome: .unknown,
                ranLivePopup: false,
                notes: "packageUnavailable"
            )
        }

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        var domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
        var snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        if result.opened {
            domProbe = try await waitForBaselineDOMProbe(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID,
                allowMissingBaselineMarker: true
            )
            snapshot = try await waitForPopupBridgeSnapshot(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        let resourceDiagnostics = snapshot.map {
            ChromeMV3PopupOptionsHostResourceLoadDiagnostics.summarize(
                events: $0.jsDebugRouteEvents
            )
        }

        let outcome = ChromeMV3ControlledPopupBaselineClassifier.classifyProtonPass(
            opened: result.opened,
            preflightBlocker: result.blocker,
            snapshot: snapshot,
            domProbe: domProbe
        )

        var notes = "observed classification only; no product support claim"
        if let resourceDiagnostics {
            notes +=
                " firstResourceBlocker=\(resourceDiagnostics.firstBlocker.rawValue)"
            if let first = resourceDiagnostics.firstFailingResource {
                notes +=
                    " firstResourceCategory=\(first.resourceCategory)"
                notes += " urlOriginClass=\(first.urlOriginClass)"
            }
        }

        return ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: ChromeMV3ControlledPopupBaselineExtensionID.protonPass.rawValue,
            layer: .realExtensionAppSpecific,
            outcome: outcome,
            ranLivePopup: result.opened,
            notes: notes
        )
    }

    #if DEBUG
    @MainActor
    func testProtonPassControlledPopupFirstResourceLoadBlockerClassification()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup baseline matrix requires macOS 15.5.")
        }
        let row = try await evaluateProtonPassExtensionRow()
        XCTAssertNotEqual(
            row.outcome,
            .resourceLoadFailure,
            "Proton Pass package-local popup resources should not be classified as generic resourceLoadFailure after optional source map probe filtering."
        )
        let packageRoot = mv3TestExtensionsRoot.appendingPathComponent(
            "Proton",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            throw XCTSkip("Proton Pass fixture package is unavailable.")
        }

        XCTAssertTrue(row.ranLivePopup, row.notes)

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )
        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }
        XCTAssertTrue(result.opened, result.message ?? "popup blocked")
        let snapshot = try await waitForPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let summary = ChromeMV3PopupOptionsHostResourceLoadDiagnostics.summarize(
            events: snapshot.jsDebugRouteEvents
        )
        let attachment = XCTAttachment(
            string: """
            rowOutcome=\(row.outcome.rawValue)
            rowNotes=\(row.notes)
            firstBlocker=\(summary.firstBlocker.rawValue)
            firstCategory=\(summary.firstFailingResource?.resourceCategory ?? "none")
            urlOriginClass=\(summary.firstFailingResource?.urlOriginClass ?? "none")
            mimeCategory=\(summary.firstFailingResource?.mimeCategory ?? "none")
            counts=\(summary.countsByCategory)
            """
        )
        attachment.name = "proton-pass-first-resource-load-blocker"
        attachment.lifetime = .keepAlways
        add(attachment)
        let resourceErrors = snapshot.jsDebugRouteEvents
            .filter { $0.eventKind == "resourceLoadError" }
            .map { event in
                [
                    "seq=\(event.sequence)",
                    "api=\(event.apiName)",
                    "classifier=\(event.resultClassifier ?? "nil")",
                    "diagnostics=\(event.diagnostics.joined(separator: ";"))",
                ].joined(separator: " ")
            }
            .joined(separator: "\n")
        let classificationLine =
            """
            firstBlocker=\(summary.firstBlocker.rawValue)
            category=\(summary.firstFailingResource?.resourceCategory ?? "none")
            origin=\(summary.firstFailingResource?.urlOriginClass ?? "none")
            mime=\(summary.firstFailingResource?.mimeCategory ?? "none")
            counts=\(summary.countsByCategory)
            resourceErrors:
            \(resourceErrors)
            """
        let resourceLoadErrors = snapshot.jsDebugRouteEvents.filter {
            $0.eventKind == "resourceLoadError"
                && ChromeMV3PopupOptionsHostResourceLoadDiagnostics
                    .isOptionalSourceMapProbeEvent($0) == false
        }
        XCTAssertTrue(
            resourceLoadErrors.isEmpty,
            "Non-optional popup resources should load without resourceLoadError.\n\(classificationLine)"
        )
        if summary.firstFailingResource != nil {
            XCTAssertNotEqual(
                summary.firstBlocker,
                .unknown,
                classificationLine
            )
        }
    }
    @MainActor
    func testProtonPassControlledPopupFirstPostResourceBlockerClassification()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Controlled popup baseline matrix requires macOS 15.5.")
        }
        let row = try await evaluateProtonPassExtensionRow()
        XCTAssertNotEqual(
            row.outcome,
            .resourceLoadFailure,
            "Required popup resources must load before post-resource classification."
        )
        let packageRoot = mv3TestExtensionsRoot.appendingPathComponent(
            "Proton",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            throw XCTSkip("Proton Pass fixture package is unavailable.")
        }
        XCTAssertTrue(row.ranLivePopup, row.notes)

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )
        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )
        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }
        XCTAssertTrue(result.opened, result.message ?? "popup blocked")
        let domProbe = try await waitForBaselineDOMProbe(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID,
            allowMissingBaselineMarker: true
        )
        let snapshot = try await waitForPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let resourceLoadErrors = snapshot.jsDebugRouteEvents.filter {
            $0.eventKind == "resourceLoadError"
                && ChromeMV3PopupOptionsHostResourceLoadDiagnostics
                    .isOptionalSourceMapProbeEvent($0) == false
        }
        XCTAssertTrue(
            resourceLoadErrors.isEmpty,
            "Required popup resources must load cleanly before post-resource triage."
        )

        let postResource = ChromeMV3ControlledPopupPostResourceClassifier
            .classifyWithSummary(
                snapshot: snapshot,
                domProbe: domProbe
            )
        let attachment = XCTAttachment(
            string: """
            rowOutcome=\(row.outcome.rawValue)
            rowNotes=\(row.notes)
            postResourceBlocker=\(postResource.blocker.rawValue)
            scriptsExecuted=\(postResource.scriptsExecuted)
            bridgeBootstrapSucceeded=\(postResource.bridgeBootstrapSucceeded)
            diagnostics:
            \(postResource.lines.joined(separator: "\n"))
            """
        )
        attachment.name = "proton-pass-first-post-resource-blocker"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(
            row.outcome,
            postResource.blocker.baselineOutcome,
            "Matrix row outcome should match post-resource classifier."
        )
        XCTAssertEqual(
            postResource.blocker,
            .popupLocalScriptFailure,
            "Proton Pass first post-resource blocker after required resources load."
        )
        XCTAssertTrue(postResource.scriptsExecuted)
        XCTAssertTrue(postResource.bridgeBootstrapSucceeded)
        XCTAssertNotEqual(
            row.outcome,
            .usableUI,
            "Proton Pass does not reach usable UI in this bounded pass."
        )
    }
    #endif

    @MainActor
    private func evaluateSumiUsablePopupExtensionRow() async throws
        -> ChromeMV3ControlledPopupBaselineMatrixRow
    {
        guard let packageRoot =
            ChromeMV3RealPackageUsablePopupFixtureLocation.packageRoot()
        else {
            return ChromeMV3ControlledPopupBaselineMatrixRow(
                rowID: ChromeMV3ControlledPopupBaselineExtensionID.sumiUsablePopup
                    .rawValue,
                layer: .realExtensionAppSpecific,
                outcome: .unknown,
                ranLivePopup: false,
                notes: "packageUnavailable"
            )
        }

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        var domProbe: ChromeMV3ControlledPopupBaselineDOMProbe?
        var snapshot: ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        if result.opened {
            domProbe = try await waitForBaselineDOMProbe(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
            snapshot = try await waitForPopupBridgeSnapshot(
                module: module,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        let outcome = ChromeMV3ControlledPopupBaselineClassifier
            .classifyRealPackageUsablePopup(
                opened: result.opened,
                preflightBlocker: result.blocker,
                domProbe: domProbe,
                snapshot: snapshot
            )

        return ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: ChromeMV3ControlledPopupBaselineExtensionID.sumiUsablePopup
                .rawValue,
            layer: .realExtensionAppSpecific,
            outcome: outcome,
            ranLivePopup: result.opened,
            notes: result.opened
                ? "localUnpackedRealPackageFixture controlledCompatibilityActionPopup"
                : (result.blocker?.rawValue ?? "blocked")
        )
    }

    @MainActor
    private func evaluateOnePasswordPreflightRow() async throws
        -> ChromeMV3ControlledPopupBaselineMatrixRow
    {
        let packageRoot = mv3TestExtensionsRoot.appendingPathComponent(
            "1password",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            return ChromeMV3ControlledPopupBaselineMatrixRow(
                rowID: ChromeMV3ControlledPopupBaselineExtensionID.onePassword
                    .rawValue,
                layer: .realExtensionAppSpecific,
                outcome: .unknown,
                ranLivePopup: false,
                notes: "packageUnavailable"
            )
        }

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        let outcome = ChromeMV3ControlledPopupBaselineClassifier
            .classifyOnePasswordPreflight(blocker: result.blocker)

        return ChromeMV3ControlledPopupBaselineMatrixRow(
            rowID: ChromeMV3ControlledPopupBaselineExtensionID.onePassword.rawValue,
            layer: .realExtensionAppSpecific,
            outcome: outcome,
            ranLivePopup: false,
            notes: "preflight only; module service worker type=module"
        )
    }

    // MARK: - Matrix helpers

    private func firstFailingMinimalFixtureLayer(
        in rows: [ChromeMV3ControlledPopupBaselineMatrixRow]
    ) -> (
        fixtureID: ChromeMV3ControlledPopupBaselineFixtureID,
        outcome: ChromeMV3ControlledPopupBaselineOutcome
    )? {
        for fixtureID in ChromeMV3ControlledPopupBaselineFixtureID.allCases {
            guard let row = rows.first(where: { $0.rowID == fixtureID.rawValue })
            else { continue }
            if row.outcome != .usableUI {
                return (fixtureID, row.outcome)
            }
        }
        return nil
    }

    private func attachMatrix(
        _ rows: [ChromeMV3ControlledPopupBaselineMatrixRow]
    ) {
        let lines = rows.map { row in
            [
                "row=\(row.rowID)",
                "layer=\(row.layer.rawValue)",
                "outcome=\(row.outcome.rawValue)",
                "ranLivePopup=\(row.ranLivePopup)",
                "notes=\(row.notes)",
            ].joined(separator: " ")
        }
        let attachment = XCTAttachment(
            string: lines.joined(separator: "\n")
        )
        attachment.name = "controlled-popup-baseline-matrix"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Popup wait helpers

    @MainActor
    private func waitForRealExtensionPopupDOMProbe(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3ControlledPopupBaselineDOMProbe {
        let script = """
        (() => {
          const text = document.body && document.body.innerText
            ? document.body.innerText.trim()
            : "";
          const inputCount =
            document.querySelectorAll('input,textarea,select').length;
          const buttonCount =
            document.querySelectorAll(
              'button,[role="button"],input[type="button"],input[type="submit"]'
            ).length;
          const linkCount = document.querySelectorAll('a[href]').length;
          const controlCount = inputCount + buttonCount + linkCount;
          const coarseUsable =
            (inputCount > 0 && buttonCount > 0)
            || (controlCount >= 2 && text.length > 0)
            || (controlCount >= 2 && buttonCount > 0);
          return JSON.stringify({
            outcome: coarseUsable ? 'ok' : 'pending',
            hasButton: buttonCount > 0,
            visibleTextLength: text.length,
            controlCount: controlCount,
            coarseUsable: coarseUsable
          });
        })();
        """
        for _ in 0..<240 {
            let raw = try await module
                .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                    profileID: profileID,
                    extensionID: extensionID,
                    script: script
                ) as? String
            if let raw,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
            {
                let probe = ChromeMV3ControlledPopupBaselineDOMProbe(
                    outcome: object["outcome"] as? String ?? "pending",
                    hasButton: object["hasButton"] as? Bool ?? false,
                    visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
                    controlCount: object["controlCount"] as? Int ?? 0,
                    coarseUsable: object["coarseUsable"] as? Bool ?? false
                )
                if probe.coarseUsable {
                    return probe
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let raw = try await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: script
            ) as? String ?? "{}"
        let object =
            raw.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        return ChromeMV3ControlledPopupBaselineDOMProbe(
            outcome: object["outcome"] as? String ?? "pending",
            hasButton: object["hasButton"] as? Bool ?? false,
            visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
            controlCount: object["controlCount"] as? Int ?? 0,
            coarseUsable: object["coarseUsable"] as? Bool ?? false
        )
    }

    @MainActor
    private func waitForBaselineDOMProbe(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String,
        allowMissingBaselineMarker: Bool = false
    ) async throws -> ChromeMV3ControlledPopupBaselineDOMProbe {
        let script = """
        (() => {
          const status = document.getElementById('baseline-status');
          const button = document.getElementById('baseline-button');
          const text = document.body && document.body.innerText
            ? document.body.innerText.trim()
            : "";
          const outcome = status
            ? (status.dataset.outcome || 'missing')
            : 'missing';
          const coarseUsable =
            outcome === 'ok'
            && !!button
            && text.length > 0;
          return JSON.stringify({
            outcome: outcome,
            hasButton: !!button,
            visibleTextLength: text.length,
            controlCount: document.querySelectorAll(
              'button,input,a[href]'
            ).length,
            coarseUsable: coarseUsable
          });
        })();
        """
        for _ in 0..<240 {
            let raw = try await module
                .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                    profileID: profileID,
                    extensionID: extensionID,
                    script: script
                ) as? String
            if let raw,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
            {
                let probe = ChromeMV3ControlledPopupBaselineDOMProbe(
                    outcome: object["outcome"] as? String ?? "missing",
                    hasButton: object["hasButton"] as? Bool ?? false,
                    visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
                    controlCount: object["controlCount"] as? Int ?? 0,
                    coarseUsable: object["coarseUsable"] as? Bool ?? false
                )
                if probe.outcome == "ok" || probe.outcome == "fail" {
                    return probe
                }
                if allowMissingBaselineMarker,
                   probe.outcome == "missing",
                   probe.visibleTextLength > 0
                {
                    return probe
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let raw = try await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: script
            ) as? String ?? "{}"
        let object =
            raw.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        return ChromeMV3ControlledPopupBaselineDOMProbe(
            outcome: object["outcome"] as? String ?? "missing",
            hasButton: object["hasButton"] as? Bool ?? false,
            visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
            controlCount: object["controlCount"] as? Int ?? 0,
            coarseUsable: object["coarseUsable"] as? Bool ?? false
        )
    }

    @MainActor
    private func waitForPopupBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        for _ in 0..<240 {
            if let snapshot =
                module.chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                    profileID: profileID,
                    extensionID: extensionID
                ),
                snapshot.jsDebugRouteEvents.isEmpty == false
            {
                let manifestReturned = snapshot.jsDebugRouteEvents.contains {
                    $0.apiName == "runtime.getManifest"
                        && $0.resultClassifier == "manifestReturned"
                }
                let finalCheckpoint = snapshot.jsDebugRouteEvents.contains {
                    $0.eventKind == "postBootstrapCheckpoint"
                        && $0.diagnostics.contains("phase=final")
                }
                if manifestReturned && finalCheckpoint {
                    return snapshot
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(
            module.chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                profileID: profileID,
                extensionID: extensionID
            ),
            "No controlled popup bridge diagnostics snapshot was captured."
        )
    }

    // MARK: - Fixture harness

    private func makeFixtureDirectory(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (relativePath, contents) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    @MainActor
    private func makeModule(
        enabled: Bool,
        includesModelContext: Bool = false,
        useFileBackedPopupHost: Bool = false
    ) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let loadingMode: ChromeMV3ProductPopupOptionsLoadingMode =
            .controlledCompatibilityDefault
        _ = useFileBackedPopupHost
        let popupFactory: @MainActor () -> ChromeMV3PopupOptionsWebViewFactory =
            {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: loadingMode
                )
            }
        guard includesModelContext else {
            return SumiExtensionsModule(
                moduleRegistry: registry,
                chromeMV3PopupOptionsWebViewFactory: popupFactory
            )
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container),
            chromeMV3PopupOptionsWebViewFactory: popupFactory
        )
    }

    @MainActor
    private func makeLiveTabModuleFixture(
        profileName: String
    ) throws -> BaselineLiveTabModuleFixture {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: profileName)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { context, initialProfile, browserConfiguration in
                ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            },
            chromeMV3PopupOptionsWebViewFactory: {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: .controlledCompatibilityDefault
                )
            }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile

        return BaselineLiveTabModuleFixture(
            defaultsHarness: harness,
            container: container,
            browserConfiguration: browserConfiguration,
            module: module,
            browserManager: browserManager,
            profile: profile
        )
    }

    @MainActor
    private func waitForEnabledExtension(
        in module: SumiExtensionsModule,
        extensionId: String
    ) async -> InstalledExtension? {
        for _ in 0..<20 {
            if let installedExtension = module.surfaceStore.enabledExtensions.first(
                where: { $0.id == extensionId }
            ) {
                return installedExtension
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return module.surfaceStore.enabledExtensions.first {
            $0.id == extensionId
        }
    }

    private func syntheticPageContext(
        profileID: String
    ) -> ChromeMV3URLHubCurrentPageContext {
        ChromeMV3URLHubCurrentPageContext(
            profileID: profileID,
            tabID: "baseline-test-tab",
            permissionBrokerTabID: 42,
            documentID: "baseline-test-document",
            urlString:
                ChromeMV3URLHubDeveloperPreviewModelBuilder
                .syntheticDiagnosticURLString,
            tabSurface: .normalTab
        )
    }
}

@MainActor
private struct BaselineLiveTabModuleFixture {
    let defaultsHarness: TestDefaultsHarness
    let container: ModelContainer
    let browserConfiguration: BrowserConfiguration
    let module: SumiExtensionsModule
    let browserManager: BrowserManager
    let profile: Profile

    func makeTab(
        url: URL = URL(string: "https://example.com/article")!
    ) -> Tab {
        let tab = Tab(
            url: url,
            name: url.host ?? "Baseline Materialized Tab",
            favicon: "globe",
            index: 0,
            browserManager: browserManager
        )
        tab.profileId = profile.id
        return tab
    }

    func tearDown() {
        _ = module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
            trigger: .explicitReset
        )
        module.setEnabled(false)
        defaultsHarness.reset()
    }
}

#if canImport(WebKit)
@MainActor
private final class BaselineMaterializedTabNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(navigation: WKNavigation?) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            if navigation == nil {
                continuation.resume()
                self.continuation = nil
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif
