import Foundation
import XCTest

@testable import Sumi

#if DEBUG
final class ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapterTests:
    XCTestCase
{
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testPolicyIsDefaultOffSyntheticReviewedFileIsolatedTopFrameOnly() {
        let policy =
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionPolicy
            .bitwardenDetectFill

        XCTAssertTrue(
            policy.webKitProgrammaticInjectionAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            policy.webKitProgrammaticInjectionAvailableByDefault
        )
        XCTAssertTrue(policy.syntheticHarnessOnly)
        XCTAssertTrue(policy.reviewedGeneratedBundleFileOnly)
        XCTAssertTrue(policy.isolatedWorldOnly)
        XCTAssertTrue(policy.topFrameOnly)
        XCTAssertFalse(policy.mainWorldAllowed)
        XCTAssertFalse(policy.multiFrameAllowed)
        XCTAssertFalse(policy.fileSchemeAllowed)
        XCTAssertFalse(policy.productNormalTabAllowed)
        XCTAssertTrue(policy.teardownRequired)
    }

    @MainActor
    func testDisabledModuleAndDefaultGateBlockWebKitObjectCreation()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        var disabled = fixture.adapterRequest()
        disabled.moduleState = .disabled
        let disabledResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(disabled)

        XCTAssertFalse(disabledResult.allowed)
        XCTAssertTrue(disabledResult.blockers.contains(.moduleDisabled))
        XCTAssertFalse(disabledResult.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(disabledResult.teardown.completed)

        var gateClosed = fixture.adapterRequest()
        gateClosed.localExperimentalGateAllowed = false
        let gateClosedResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(gateClosed)

        XCTAssertFalse(gateClosedResult.allowed)
        XCTAssertTrue(
            gateClosedResult.blockers.contains(.localExperimentalGateClosed)
        )
        XCTAssertFalse(gateClosedResult.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(gateClosedResult.teardown.completed)
    }

    @MainActor
    func testReviewedGeneratedScriptExecutesInIsolatedTopFrameAndTearsDown()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(try makeFixture().adapterRequest())

        XCTAssertTrue(result.allowed, "\(result.blockers): \(result.diagnostics)")
        XCTAssertEqual(
            result.injectedReviewedFile,
            "content/bootstrap-autofill.js"
        )
        XCTAssertTrue(result.isolatedWorldUsed)
        XCTAssertTrue(result.topFrameOnly)
        XCTAssertTrue(result.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(result.nonPersistentWebsiteDataStoreUsed)
        XCTAssertEqual(result.userScriptAttachmentCount, 0)
        XCTAssertEqual(result.scriptMessageHandlerAttachmentCount, 1)
        XCTAssertTrue(result.navigationCompleted)
        XCTAssertTrue(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.fixedHarnessShimInstalled)
        XCTAssertTrue(result.fixedDetectFillDispatchCompleted)
        XCTAssertTrue(result.dummyValuesWrittenByActualWebKitExecutedScript)
        XCTAssertEqual(
            result.domObservationBefore.url,
            "https://sumi.local.test/login"
        )
        XCTAssertEqual(
            result.domObservationBefore.origin,
            "https://sumi.local.test"
        )
        XCTAssertTrue(result.domObservationBefore.initialValuesEmpty)
        XCTAssertEqual(
            result.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            result.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(result.domObservationAfter.finalValuesMatchDummyFill)
        XCTAssertTrue(result.teardown.completed)
        XCTAssertTrue(result.teardown.navigationDelegateDetached)
        XCTAssertEqual(result.teardown.userScriptCountAfterTeardown, 0)
        XCTAssertEqual(
            result.teardown.scriptMessageHandlerCountAfterTeardown,
            0
        )
        XCTAssertTrue(result.teardown.webViewReferenceReleased)
        XCTAssertTrue(result.teardown.configurationReferenceReleased)
    }

    @MainActor
    func testMainWorldMultiFrameAndNonReviewedGeneratedScriptRemainBlocked()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        var mainWorld = fixture.adapterRequest()
        mainWorld.world = "MAIN"
        let mainWorldResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(mainWorld)
        XCTAssertTrue(mainWorldResult.blockers.contains(.isolatedWorldRequired))
        XCTAssertFalse(mainWorldResult.hiddenSyntheticWebViewCreated)

        var multiFrame = fixture.adapterRequest()
        multiFrame.frameIDs = [0, 1]
        multiFrame.allFrames = true
        let multiFrameResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(multiFrame)
        XCTAssertTrue(multiFrameResult.blockers.contains(.multiFrameBlocked))
        XCTAssertFalse(multiFrameResult.hiddenSyntheticWebViewCreated)

        var nonReviewedRequest = fixture.modeledRequest()
        nonReviewedRequest.files = ["content/not-reviewed.js"]
        let nonReviewedAttempt =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            .attempt(nonReviewedRequest)
        var nonReviewed = fixture.adapterRequest()
        nonReviewed.modeledInjectionAttempt = nonReviewedAttempt
        let nonReviewedResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(nonReviewed)
        XCTAssertTrue(
            nonReviewedResult.blockers
                .contains(.reviewedGeneratedBundleFileRequired)
        )
        XCTAssertFalse(nonReviewedResult.hiddenSyntheticWebViewCreated)
    }

    @MainActor
    func testExplicitAsyncRealPackageRunnerExecutesReviewedLocalBitwardenBundle()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let target = try XCTUnwrap(
            ChromeMV3PasswordManagerRealPackageTargetCatalog
                .explicitLocalTargets()
                .first { $0.targetClass == .bitwarden }
        )
        guard FileManager.default.fileExists(
            atPath: target.explicitAllowedLocalRoot
        ) else {
            throw XCTSkip("Local reviewed Bitwarden package is unavailable.")
        }
        let report = await
            ChromeMV3PasswordManagerRealPackageTrialRunner
            .runWithSyntheticWebKitProgrammaticInjectionAdapter(
                rootURL: try temporaryDirectory(),
                targets: [target],
                serviceWorkerTrialGateSource: .explicitTestTrial,
                writeReport: false,
                now: { Date(timeIntervalSince1970: 22) }
            )
        let row = try XCTUnwrap(report.rows.first)
        let detectFill = row.bitwardenE2ESmoke.detectFillSmoke
        let adapter = detectFill.webKitProgrammaticInjectionResult

        XCTAssertEqual(row.packageSource, .realLocalUnpacked)
        XCTAssertTrue(adapter.allowed, "\(adapter.blockers): \(adapter.diagnostics)")
        XCTAssertTrue(adapter.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(adapter.dummyValuesWrittenByActualWebKitExecutedScript)
        XCTAssertTrue(adapter.teardown.completed)
        XCTAssertTrue(detectFill.modeledDummyFillChangedDOM)
        XCTAssertEqual(
            detectFill.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            detectFill.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(
            detectFill.nextBlocker.contains("stable product normal-tab")
        )
    }

    func testReviewedResolverBlocksTraversalAbsoluteRemoteFileAndSymlinkPaths()
        throws
    {
        let fixture = try makeFixture()
        let generatedBundle = fixture.modeledRequest().generatedBundle
        assertBlocked(
            "../content/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .unsafeScriptPath
        )
        assertBlocked(
            "/content/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .unsafeScriptPath
        )
        assertBlocked(
            "https://example.test/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .remoteScriptBlocked
        )
        assertBlocked(
            "file:///tmp/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .fileSchemeScriptBlocked
        )

        let symlink = fixture.generated
            .appendingPathComponent("content/symlink.js")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL:
                fixture.generated
                .appendingPathComponent("content/bootstrap-autofill.js")
        )
        let symlinkBundle =
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
                recordAvailable: true,
                rootPath: fixture.generated.path,
                copiedResourcePaths: ["content/symlink.js"]
            )
        assertBlocked(
            "content/symlink.js",
            generatedBundle: symlinkBundle,
            blocker: .generatedResourceSymbolicLink
        )
    }

    func testSourceGuardsKeepAdapterSyntheticScopedAndEventDriven() throws {
        let source = try String(
            contentsOf:
                projectRoot().appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "chrome.scripting." + "executeScript",
            "function" + "Source",
            "\"MA" + "IN\"",
            "allFrames: " + "true",
            "fileSchemeAllowed: " + "true",
            "productNormalTabAllowed: " + "true",
            "URL" + "Session",
            "WKWebExtension" + "Context(",
            "webExtension" + "Controller",
            "connect" + "Native",
            "Process" + "(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer(",
            "poll" + "ing",
            "chrome.webstore" + ".install",
            "clients2.google.com/service/update2/crx",
            "master" + "Password",
            "access" + "Token",
            "refresh" + "Token",
            "evaluateJavaScript(request",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertTrue(source.contains("WKWebsiteDataStore.nonPersistent()"))
        XCTAssertTrue(source.contains("WKContentWorld.world(name: contentWorldName)"))
        XCTAssertTrue(source.contains("frameIDs != [0]"))
        XCTAssertTrue(
            source.contains(
                "removeScriptMessageHandler(\n            forName: completionMessageHandlerName,\n            contentWorld: contentWorld"
            )
        )
    }

    private func assertBlocked(
        _ path: String,
        generatedBundle:
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle,
        blocker: ChromeMV3LocalExperimentalProgrammaticInjectionBlocker
    ) {
        let result =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession
            .resolveGeneratedBundleFile(
                path,
                generatedBundle: generatedBundle
            )
        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(
            result.blockers.contains(blocker),
            "\(path): \(result.blockers)"
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("package", isDirectory: true)
        let generated =
            root.appendingPathComponent("generated", isDirectory: true)
        try write(
            "chrome.scripting.executeScript({files:['content/bootstrap-autofill.js']}); triggerAutofillScriptInjection();",
            to: package.appendingPathComponent("background.js")
        )
        try write(
            "autofill-injected-script-port",
            to:
                package.appendingPathComponent(
                    "content/content-message-handler.js"
                )
        )
        try write(
            reviewedFixtureScript,
            to:
                package.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        try write(
            reviewedFixtureScript,
            to:
                generated.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        try write(
            "not reviewed",
            to: generated.appendingPathComponent("content/not-reviewed.js")
        )
        return Fixture(package: package, generated: generated)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct Fixture {
        var package: URL
        var generated: URL

        func modeledRequest()
            -> ChromeMV3LocalExperimentalProgrammaticInjectionRequest
        {
            ChromeMV3LocalExperimentalProgrammaticInjectionRequest(
                moduleState: .enabled,
                localExperimentalGateAllowed: true,
                extensionEnabled: true,
                profileScopedExtensionLoaded: true,
                generatedBundle:
                    ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
                        recordAvailable: true,
                        rootPath: generated.path,
                        copiedResourcePaths: [
                            "content/bootstrap-autofill.js",
                            "content/not-reviewed.js",
                        ]
                    ),
                packageRootPath: package.path,
                targetURL: "https://sumi.local.test/login",
                syntheticLoginURL: "https://sumi.local.test/login",
                tabID: 1,
                frameIDs: [0],
                allFrames: false,
                world: "ISOLATED",
                files: ["content/bootstrap-autofill.js"],
                functionSource: nil,
                arguments: [],
                injectImmediately: true,
                hostPermissionOrActiveTabAllowed: true
            )
        }

        func adapterRequest()
            -> ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest
        {
            let attempt =
                ChromeMV3LocalExperimentalProgrammaticInjectionSession()
                .attempt(modeledRequest())
            return ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest(
                moduleState: .enabled,
                localExperimentalGateAllowed: true,
                extensionEnabled: true,
                profileScopedExtensionLoaded: true,
                hostPermissionOrActiveTabAllowed: true,
                targetURL: "https://sumi.local.test/login",
                syntheticLoginURL: "https://sumi.local.test/login",
                documentID: "sumi-webkit-adapter-login-main-frame",
                navigationSequence: 1,
                frameIDs: [0],
                allFrames: false,
                world: "ISOLATED",
                dummyUsername: "sumi-test-user@example.test",
                dummyPassword: "sumi-test-password-not-secret",
                modeledInjectionAttempt: attempt
            )
        }
    }

    private var reviewedFixtureScript: String {
        """
        (() => {
          let listener;
          listener = (message, sender, sendResponse) => {
            if (message.command === "collectPageDetailsImmediately") {
              document.getElementById("sumi-login-email").opid = "__0";
              document.getElementById("sumi-login-password").opid = "__1";
              sendResponse({ fields: ["__0", "__1"] });
              return true;
            }
            if (message.command === "fillForm") {
              for (const [action, opid, value] of message.fillScript.script) {
                if (action !== "fill_by_opid") continue;
                const field = Array.from(document.querySelectorAll("input"))
                  .find((item) => item.opid === opid);
                if (field) field.value = value;
              }
              sendResponse(null);
              return true;
            }
            return null;
          };
          chrome.runtime.onMessage.addListener(listener);
          chrome.runtime.connect({ name: "autofill-injected-script-port" });
          window.bitwardenAutofillInit = {
            destroy() { chrome.runtime.onMessage.removeListener(listener); }
          };
        })();
        """
    }
}
#endif
