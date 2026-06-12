//
//  AuxiliaryWindowRegressionGuardTests.swift
//  SumiTests
//

@testable import Sumi
import XCTest

final class AuxiliaryWindowRegressionGuardTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testActionPopupRoutesDoNotReferenceAuxiliaryWindowManager() throws {
        let controllerDelegate = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let presentStart = try XCTUnwrap(
            controllerDelegate.range(of: "presentActionPopup action:")?.lowerBound
        )
        let presentEnd = controllerDelegate[presentStart...].range(of: "\n    func ")?.lowerBound
            ?? controllerDelegate.endIndex
        let presentBody = String(controllerDelegate[presentStart..<presentEnd])
        XCTAssertFalse(presentBody.contains("auxiliaryWindowManager"))
        XCTAssertFalse(presentBody.contains("AuxiliaryWindowManager"))

        let forbiddenPaths = [
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift",
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift",
        ]

        for path in forbiddenPaths {
            let fileSource = try source(path)
            if path.contains("ExtensionManager+UI.swift") {
                let openActionStart = try XCTUnwrap(
                    fileSource.range(of: "func openActionPopupFromURLHub")?.lowerBound
                )
                let openActionEnd = fileSource[openActionStart...].range(of: "\n    func ")?.lowerBound
                    ?? fileSource.endIndex
                let openActionBody = String(fileSource[openActionStart..<openActionEnd])
                XCTAssertFalse(openActionBody.contains("auxiliaryWindowManager"))
            } else {
                XCTAssertFalse(fileSource.contains("auxiliaryWindowManager"), path)
                XCTAssertFalse(fileSource.contains("AuxiliaryWindowManager"), path)
            }
        }
    }

    func testMiniWindowRoutesPreserveWebKitConfigurationSemantics() throws {
        let popupResponder = try source(
            "Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"
        )
        let managerSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift"
        )
        let tabRuntimeSource = try source(
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift"
        )

        XCTAssertTrue(
            popupResponder.contains("auxiliaryWindowManager.presentWebPopup")
            || popupResponder.contains("auxiliaryWindowManager.presentExtensionExternalWebPopup")
        )
        XCTAssertTrue(
            tabRuntimeSource.contains("makeWebViewPreservingWebKitConfiguration")
            || tabRuntimeSource.contains("AuxiliaryWebViewFactory")
        )
        XCTAssertFalse(managerSource.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(managerSource.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(
            managerSource.contains("webView.load("),
            "Primary mini-window presentation must not manually load requests"
        )
    }

    func testExtensionPopupExternalLoadDoesNotInheritExtensionContextOverride() throws {
        let managerSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift"
        )
        let profilesSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )
        let popupStart = try XCTUnwrap(
            managerSource.range(of: "func presentExtensionPopupWindow")?.lowerBound
        )
        let popupEnd = managerSource[popupStart...].range(of: "\n    func teardown")?.lowerBound
            ?? managerSource.endIndex
        let popupBody = String(managerSource[popupStart..<popupEnd])

        XCTAssertTrue(popupBody.contains("let isExtensionOwnedLoad = ExtensionUtils.isExtensionOwnedURL(loadURL)"))
        XCTAssertTrue(popupBody.contains("let tabWebExtensionContextOverride = resolvedExtensionLoad.context"))
        XCTAssertTrue(popupBody.contains("?? (isExtensionOwnedLoad ? extensionContext : nil)"))
        XCTAssertTrue(popupBody.contains("webExtensionContextOverride: tabWebExtensionContextOverride"))
        XCTAssertFalse(popupBody.contains("resolvedExtensionLoad.context ?? extensionContext"))
        XCTAssertFalse(
            popupBody.contains("miniTab.loadWebViewIfNeeded()"),
            "Extension popup windows must not load before auxiliary session and mini-window adapter registration"
        )
        XCTAssertTrue(
            popupBody.contains("createAuxiliaryMiniWindowWebViewFromWebKitConfiguration"),
            "Extension popup windows should create the auxiliary WebView without triggering Tab.setupWebView early-load behavior"
        )
        XCTAssertLessThan(
            try XCTUnwrap(popupBody.range(of: "notifyAuxiliaryWindowOpened(session)")?.lowerBound),
            try XCTUnwrap(popupBody.range(of: "miniTab.loadURL(loadURL)")?.lowerBound),
            "WebExtension runtime must learn about the mini-window before the extension page can call windows APIs"
        )

        let uiSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )
        XCTAssertTrue(uiSource.contains("Self.isExtensionExternalWebPopupURL(firstURL)"))
        XCTAssertFalse(uiSource.contains("OAuthDetector.isLikelyOAuthPopupURL(firstURL)"))
        XCTAssertTrue(managerSource.contains("notifyAuxiliaryWindowOpened(session)"))
        XCTAssertTrue(managerSource.contains("notifyAuxiliaryWindowClosed(session)"))
        XCTAssertTrue(profilesSource.contains("extensionContext.didOpenWindow(adapter)"))
        XCTAssertTrue(profilesSource.contains("extensionContext.didFocusWindow(adapter)"))
        XCTAssertTrue(profilesSource.contains("extensionContext.didCloseWindow(adapter)"))
    }

    func testAuxiliaryManagerDoesNotMutateParentWindowFrame() throws {
        let managerSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift"
        )
        let resolverSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowGeometryResolver.swift"
        )
        let bridgeSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionBridge.swift"
        )

        for source in [managerSource, resolverSource] {
            XCTAssertFalse(source.contains("parentWindow?.setFrame"))
            XCTAssertFalse(source.contains("openerWindow?.setFrame"))
            XCTAssertFalse(source.contains("parentWindow?.setContentSize"))
            XCTAssertFalse(source.contains("openerWindow?.setContentSize"))
        }

        XCTAssertTrue(
            bridgeSource.contains("func window(for extensionContext:"),
            "Extension tab adapters must route auxiliary tabs to mini-window adapters"
        )
        XCTAssertTrue(
            bridgeSource.contains("ExtensionMiniWindowAdapter"),
            "Mini-window adapter must implement extension window surface"
        )
        XCTAssertFalse(
            bridgeSource.contains("redirectedMiniWindowAdapter"),
            "Main WebExtension window adapters must not proxy arbitrary operations to mini-window adapters"
        )
        XCTAssertFalse(
            bridgeSource.contains("AuxiliaryWindowRuntime"),
            "Temporary runtime diagnostics should not be left in the window adapter path"
        )
    }

    func testMiniWindowPresentationActivatesBeforeKeyingWindow() throws {
        let compactWindowSource = try source(
            "Sumi/Components/Window/AuxiliaryCompactWindow.swift"
        )
        let bridgeSource = try source(
            "Sumi/Managers/ExtensionManager/ExtensionBridge.swift"
        )
        let externalMiniWindowSource = try source(
            "Sumi/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift"
        )

        let presentStart = try XCTUnwrap(
            compactWindowSource.range(of: "func present(shouldActivateApp: Bool)")?.lowerBound
        )
        let presentBody = String(compactWindowSource[presentStart...])
        XCTAssertLessThan(
            try XCTUnwrap(presentBody.range(of: "NSApp.activate")?.lowerBound),
            try XCTUnwrap(presentBody.range(of: "makeKeyAndOrderFront")?.lowerBound)
        )

        let miniFocusStart = try XCTUnwrap(
            bridgeSource.range(of: "final class ExtensionMiniWindowAdapter")?.lowerBound
        )
        let miniFocusBody = String(bridgeSource[miniFocusStart...])
        XCTAssertLessThan(
            try XCTUnwrap(miniFocusBody.range(of: "NSApp.activate")?.lowerBound),
            try XCTUnwrap(miniFocusBody.range(of: "makeKeyAndOrderFront")?.lowerBound)
        )

        let presentSessionStart = try XCTUnwrap(
            externalMiniWindowSource.range(of: "sessions[session.id] = SessionEntry(controller: controller)")?.lowerBound
        )
        let presentSessionBody = String(externalMiniWindowSource[presentSessionStart...])
        XCTAssertLessThan(
            try XCTUnwrap(presentSessionBody.range(of: "NSApp.activate")?.lowerBound),
            try XCTUnwrap(presentSessionBody.range(of: "controller.showWindow")?.lowerBound)
        )
    }

    func testCloseAllForExtensionIdUsesExplicitOwnerExtensionID() throws {
        let managerSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift"
        )
        let sessionSource = managerSource[
            (managerSource.range(of: "func closeAll(")?.lowerBound ?? managerSource.startIndex)...
        ]
        let closeAllEnd = sessionSource.range(of: "\n    // MARK: - Private")?.lowerBound
            ?? sessionSource.endIndex
        let closeAllBody = String(sessionSource[..<closeAllEnd])

        XCTAssertTrue(closeAllBody.contains("session.ownerExtensionID == extensionId"))
        XCTAssertFalse(closeAllBody.contains("webExtensionContextOverride"))
        XCTAssertTrue(managerSource.contains("let ownerExtensionID: String?"))
    }

    func testNestedSizedPopupOverDepthDoesNotUseInPlaceLoad() throws {
        let delegateSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowUIDelegate.swift"
        )

        XCTAssertTrue(delegateSource.contains("let isSizedPopup = windowFeatures.width != nil"))
        XCTAssertTrue(delegateSource.contains("nestedDepth < manager.maxNestedDepth"))
        XCTAssertTrue(delegateSource.contains("Blocked nested sized popup"))
        XCTAssertTrue(delegateSource.contains("// Unsized nested popups keep the configured in-place load policy."))
    }

    func testAuxiliaryUIDelegateMatchesWebKitCompletionHandlerAnnotations() throws {
        let delegateSource = try source(
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowUIDelegate.swift"
        )

        XCTAssertTrue(delegateSource.contains("@escaping @MainActor @Sendable () -> Void"))
        XCTAssertTrue(delegateSource.contains("@escaping @MainActor @Sendable (Bool) -> Void"))
        XCTAssertTrue(delegateSource.contains("@escaping @MainActor @Sendable (String?) -> Void"))
        XCTAssertTrue(delegateSource.contains("@escaping @MainActor @Sendable ([URL]?) -> Void"))
        XCTAssertTrue(delegateSource.contains("func webViewDidClose(_ webView: WKWebView)"))
        XCTAssertTrue(delegateSource.contains("teardown(for: webView, reason: .webViewDidClose)"))
    }

    func testMiniWindowSymbolsScopedToExpectedFiles() throws {
        let allowed = [
            "Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Managers/BrowserManager/BrowserManager+WebViewLifecycle.swift",
            "Sumi/Managers/BrowserManager/BrowserManager+DialogsUtilities.swift",
            "Sumi/Managers/AuxiliaryWindowManager/AuxiliaryWindowManager.swift",
            "Sumi/Managers/ExtensionManager/ExtensionBridge.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift",
        ]

        let sumiRoot = repoRoot.appendingPathComponent("Sumi")
        let enumerator = FileManager.default.enumerator(
            at: sumiRoot,
            includingPropertiesForKeys: nil
        )

        while let next = enumerator?.nextObject() as? URL {
            guard next.pathExtension == "swift" else { continue }
            let relative = next.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let fileSource = try String(contentsOf: next, encoding: .utf8)
            guard fileSource.contains("auxiliaryWindowManager")
                || fileSource.contains("ExtensionMiniWindowAdapter")
            else {
                continue
            }
            XCTAssertTrue(
                allowed.contains(relative),
                "Unexpected auxiliary mini-window reference in \(relative)"
            )
        }
    }
}
