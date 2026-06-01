import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3LocalExperimentalProgrammaticInjectionTests:
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

    func testReviewedGeneratedBundleBootstrapAttachesAndTearsDownForEveryLifecycleBoundary()
        throws
    {
        let fixture = try makeFixture()

        for reason in [
            ChromeMV3LocalExperimentalProgrammaticInjectionTeardownReason
                .navigation,
            .extensionDisable,
            .profileTeardown,
            .smokeComplete,
        ] {
            let session =
                ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            let attempt = session.attempt(fixture.request())

            XCTAssertTrue(attempt.allowed)
            XCTAssertTrue(attempt.blockers.isEmpty)
            XCTAssertEqual(attempt.currentBlocker, "none")
            XCTAssertEqual(session.activeInjectionCount, 1)
            XCTAssertEqual(
                attempt.resourceResolutions.first?.status,
                .copiedGeneratedBundleFile
            )
            XCTAssertTrue(attempt.syntheticDOMModelAttachmentRecorded)

            session.tearDown(reason: reason)

            XCTAssertEqual(session.activeInjectionCount, 0)
            XCTAssertTrue(
                session.teardownDiagnostics.first?.contains(reason.rawValue)
                    == true
            )
        }
    }

    func testDefaultGateAndBroaderScriptingShapesRemainBlocked() throws {
        let fixture = try makeFixture()
        let baseline = fixture.request()
        var cases: [
            (
                mutate:
                    (inout ChromeMV3LocalExperimentalProgrammaticInjectionRequest)
                        -> Void,
                blocker:
                    ChromeMV3LocalExperimentalProgrammaticInjectionBlocker
            )
        ] = []
        cases.append(({ $0.localExperimentalGateAllowed = false },
                      .localExperimentalGateClosed))
        cases.append(({ $0.moduleState = .disabled }, .moduleDisabled))
        cases.append(({ $0.extensionEnabled = false }, .extensionDisabled))
        cases.append(({ $0.profileScopedExtensionLoaded = false },
                      .profileScopedExtensionMissing))
        cases.append(({ $0.hostPermissionOrActiveTabAllowed = false },
                      .hostPermissionBlocked))
        cases.append(({ $0.targetURL = "https://example.test/login" },
                      .targetOutsideSyntheticLogin))
        cases.append(({ $0.targetURL = "file:///tmp/login.html" },
                      .unsupportedTargetURLScheme))
        cases.append(({ $0.frameIDs = [0, 1] }, .multiFrameRequired))
        cases.append(({ $0.allFrames = true }, .multiFrameRequired))
        cases.append(({ $0.world = "MAIN" }, .mainWorldRequired))
        cases.append(({ $0.functionSource = "() => document.title" },
                      .arbitraryFunctionInjectionRequired))
        cases.append(({ $0.arguments = ["unexpected"] }, .argumentsBlocked))
        cases.append(({ $0.injectImmediately = false },
                      .injectImmediatelyRequired))
        cases.append(({ $0.files = ["content/contextMenuHandler.js"] },
                      .unsupportedTargetShape))

        for item in cases {
            var request = baseline
            item.mutate(&request)
            let session =
                ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            let attempt = session.attempt(request)

            XCTAssertFalse(attempt.allowed, "\(item.blocker)")
            XCTAssertTrue(
                attempt.blockers.contains(item.blocker),
                "\(item.blocker): \(attempt.blockers)"
            )
            XCTAssertEqual(session.activeInjectionCount, 0)
        }
    }

    func testGeneratedBundleResolverBlocksUnsafeMissingNonCopiedRemoteFileAndSymlinkPaths()
        throws
    {
        let fixture = try makeFixture()
        let generatedBundle = fixture.request().generatedBundle
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
            "https://example.test/bootstrap.js",
            generatedBundle: generatedBundle,
            blocker: .remoteScriptBlocked
        )
        assertBlocked(
            "file:///tmp/bootstrap.js",
            generatedBundle: generatedBundle,
            blocker: .fileSchemeScriptBlocked
        )
        assertBlocked(
            "content/not-copied.js",
            generatedBundle: generatedBundle,
            blocker: .generatedResourceNotCopied
        )

        let missing = ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
            recordAvailable: true,
            rootPath: generatedBundle.rootPath,
            copiedResourcePaths: ["content/missing.js"]
        )
        assertBlocked(
            "content/missing.js",
            generatedBundle: missing,
            blocker: .generatedResourceMissing
        )

        let symlink = URL(fileURLWithPath: try XCTUnwrap(generatedBundle.rootPath))
            .appendingPathComponent("content/symlink.js")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL:
                URL(fileURLWithPath: try XCTUnwrap(generatedBundle.rootPath))
                .appendingPathComponent("content/bootstrap-autofill.js")
        )
        let symlinkBundle =
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
                recordAvailable: true,
                rootPath: generatedBundle.rootPath,
                copiedResourcePaths: ["content/symlink.js"]
            )
        assertBlocked(
            "content/symlink.js",
            generatedBundle: symlinkBundle,
            blocker: .generatedResourceSymbolicLink
        )
    }

    func testSourceDoesNotAddProductOrArbitraryEvaluationSurface() throws {
        let source = try String(
            contentsOf:
                projectRoot().appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3LocalExperimentalProgrammaticInjection.swift"
                ),
            encoding: .utf8
        )

        for forbidden in [
            "import " + "WebKit",
            "evaluate" + "JavaScript(",
            "callAsync" + "JavaScript(",
            "WKContentWorld." + "pageWorld",
            "WKWebExtension" + "Controller(",
            "URLSession" + ".shared",
            "Process" + "()",
            "connect" + "Native",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testPolicyRemainsLocalExperimentalDefaultOffAndNarrow() {
        let policy =
            ChromeMV3LocalExperimentalProgrammaticInjectionPolicy
            .bitwardenDetectFill

        XCTAssertTrue(
            policy.programmaticInjectionAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(policy.programmaticInjectionAvailableByDefault)
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
        XCTAssertTrue(policy.generatedBundleFilesOnly)
        XCTAssertEqual(
            policy.allowedGeneratedBundleFiles,
            ["content/bootstrap-autofill.js"]
        )
        XCTAssertFalse(policy.arbitraryFunctionInjectionAllowed)
        XCTAssertFalse(policy.argumentsAllowed)
        XCTAssertFalse(policy.mainWorldAllowed)
        XCTAssertFalse(policy.multiFrameAllowed)
        XCTAssertFalse(policy.fileSchemeAllowed)
        XCTAssertFalse(policy.remoteScriptAllowed)
        XCTAssertFalse(policy.productNormalTabsAllowed)
        XCTAssertTrue(policy.requiresHostPermissionOrActiveTab)
        XCTAssertTrue(policy.teardownRequired)
    }

    private func assertBlocked(
        _ path: String,
        generatedBundle:
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle,
        blocker: ChromeMV3LocalExperimentalProgrammaticInjectionBlocker
    ) {
        let resolution =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession
            .resolveGeneratedBundleFile(
                path,
                generatedBundle: generatedBundle
            )
        XCTAssertEqual(resolution.status, .blocked)
        XCTAssertTrue(
            resolution.blockers.contains(blocker),
            "\(path): \(resolution.blockers)"
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("package", isDirectory: true)
        let generated = root.appendingPathComponent("generated", isDirectory: true)
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
            "collectPageDetailsImmediately(); fillForm();",
            to:
                package.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        try write(
            "collectPageDetailsImmediately(); fillForm();",
            to:
                generated.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
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

        func request()
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
    }
}
