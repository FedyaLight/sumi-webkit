import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerJSExecutionHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDisabledModuleAndExtensionBlockExecutionBeforeResourceLoad() throws {
        let fixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        let moduleDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(moduleState: .disabled)
        )
        let extensionDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(extensionEnabled: false)
        )

        XCTAssertEqual(moduleDisabled.start().status, .blocked)
        XCTAssertEqual(extensionDisabled.start().status, .blocked)
        XCTAssertNil(moduleDisabled.snapshot.resourceLoad)
        XCTAssertNil(extensionDisabled.snapshot.resourceLoad)
        XCTAssertNil(moduleDisabled.snapshot.lifecycleSnapshot)
        XCTAssertNil(extensionDisabled.snapshot.lifecycleSnapshot)
        XCTAssertEqual(moduleDisabled.policy.executionSurface, .none)
        XCTAssertEqual(extensionDisabled.policy.executionSurface, .none)
        XCTAssertFalse(moduleDisabled.policy.serviceWorkerJSExecutionAvailableByDefault)
        XCTAssertFalse(
            moduleDisabled.policy.dynamicImportAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            extensionDisabled.policy.dynamicImportAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            moduleDisabled.policy.dynamicImportCapabilityProbe.probeExecuted
        )
        XCTAssertFalse(
            extensionDisabled.policy.dynamicImportCapabilityProbe.probeExecuted
        )
        XCTAssertTrue(
            moduleDisabled.policy.diagnostics.contains {
                $0.contains("Module-disabled state skipped JavaScriptCore")
            }
        )
        XCTAssertTrue(
            extensionDisabled.policy.diagnostics.contains {
                $0.contains("Extension-disabled state skipped JavaScriptCore")
            }
        )
    }

    func testDefaultOffGateBlocksExecutionBeforeResourceLoad() throws {
        let fixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n"
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .blocked)
        XCTAssertNil(harness.snapshot.resourceLoad)
        XCTAssertTrue(
            harness.policy.blockers.contains(.localExperimentalGateRequired)
        )
        XCTAssertFalse(harness.policy.dynamicImportAvailableByDefault)
        XCTAssertFalse(harness.policy.dynamicImportAvailable)
        XCTAssertEqual(harness.policy.dynamicImportScope, .blocked)
    }

    func testDynamicImportCapabilityProbeReportsSupportedOrPreciseBlockers() {
        let probe = ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
            .evaluate()

        XCTAssertTrue(probe.probeExecuted)
        XCTAssertFalse(probe.dynamicImportAvailableByDefault)
        if probe.dynamicImportAvailableInLocalExperimentalGate {
            XCTAssertTrue(probe.blockers.isEmpty)
            XCTAssertEqual(probe.dynamicImportScope, .generatedBundleOnly)
            XCTAssertTrue(probe.importExpressionParses)
            XCTAssertTrue(probe.lowerLevelPublicModuleAPIAvailable)
            XCTAssertTrue(probe.sourceTextModuleLoadSupported)
            XCTAssertTrue(probe.moduleLoadingCanBeIntercepted)
            XCTAssertTrue(probe.resolverHookAvailable)
            XCTAssertTrue(probe.dynamicImportCallbackAvailable)
            XCTAssertTrue(probe.generatedRootContainmentProven)
            XCTAssertTrue(probe.promiseCompletionObservableWithoutScheduling)
            XCTAssertTrue(probe.deterministicPromiseDrainAvailable)
            XCTAssertTrue(probe.moduleNamespaceSupported)
            XCTAssertTrue(probe.sourceURLMetadataControlAvailable)
            XCTAssertTrue(probe.safeCancellationAvailable)
            XCTAssertTrue(probe.teardownWithoutPersistentRuntimeAvailable)
            XCTAssertTrue(probe.executionSurfaceSupported)
        } else {
            XCTAssertEqual(probe.dynamicImportScope, .blocked)
            XCTAssertFalse(probe.blockers.isEmpty)
            XCTAssertTrue(
                probe.blockers.contains(
                    .dynamicImportLowerLevelAPINotAvailable
                )
            )
            XCTAssertTrue(
                probe.blockers.contains(.dynamicImportResolverHookUnavailable)
            )
            XCTAssertTrue(
                probe.blockers.contains(
                    .dynamicImportGeneratedRootContainmentUnproven
                )
            )
            XCTAssertTrue(
                probe.blockers.contains(.dynamicImportPromiseDrainUnavailable)
            )
            XCTAssertTrue(
                probe.blockers.contains(
                    .dynamicImportExecutionSurfaceUnsupported
                )
            )
            XCTAssertFalse(probe.lowerLevelPublicModuleAPIAvailable)
            XCTAssertFalse(probe.sourceTextModuleLoadSupported)
            XCTAssertFalse(probe.moduleLoadingCanBeIntercepted)
            XCTAssertFalse(probe.resolverHookAvailable)
            XCTAssertFalse(probe.dynamicImportCallbackAvailable)
            XCTAssertFalse(probe.generatedRootContainmentProven)
            XCTAssertFalse(probe.deterministicPromiseDrainAvailable)
            XCTAssertFalse(probe.moduleNamespaceSupported)
            XCTAssertTrue(probe.sourceURLMetadataControlAvailable)
            XCTAssertFalse(probe.safeCancellationAvailable)
            XCTAssertTrue(probe.teardownWithoutPersistentRuntimeAvailable)
        }
    }

    func testGeneratedResourceLoaderDiagnosesMissingUnsafeAndModule()
        throws
    {
        let missingFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        try FileManager.default.removeItem(
            at: missingFixture.generatedRootURL
                .appendingPathComponent("background.js")
        )
        let missing = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: missingFixture.request()
        )
        XCTAssertEqual(missing.start().status, .blocked)
        XCTAssertTrue(
            missing.snapshot.resourceLoad?.blockers.contains(
                .serviceWorkerFileMissing
            ) == true
        )

        let unsafeFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        var unsafeManifest = unsafeFixture.manifest
        unsafeManifest.background?.serviceWorker = "../background.js"
        let unsafe = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: unsafeFixture.request(manifest: unsafeManifest)
        )
        XCTAssertEqual(unsafe.start().status, .blocked)
        XCTAssertTrue(
            unsafe.snapshot.resourceLoad?.blockers.contains(
                .serviceWorkerPathUnsafe
            ) == true
        )

        let moduleFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            serviceWorkerType: "module",
            localExperimentalGateAllowed: true
        )
        let module = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: moduleFixture.request()
        )
        XCTAssertEqual(module.start().status, .blocked)
        XCTAssertTrue(
            module.snapshot.resourceLoad?.blockers.contains(
                .moduleWorkerUnsupported
            ) == true
        )
        XCTAssertFalse(module.policy.moduleWorkerImportAvailable)

    }

    func testImportScriptsPolicyAndRelativeImportCaptureListener() throws {
        let fixture = try makeHarness(
            source: "importScripts('./dependency.js');\n",
            extraFiles: [
                "dependency.js": """
                chrome.runtime.onMessage.addListener((message) => {
                  return { fromImport: message.value };
                });
                """,
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        let started = harness.start()
        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["value": .string("dependency")])],
            payloadSummary: "imported runtime.onMessage"
        )

        XCTAssertEqual(started.status, .running)
        XCTAssertTrue(harness.policy.importScriptsAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.importScriptsAvailableByDefault)
        XCTAssertEqual(harness.policy.importScriptsScope, .generatedBundleOnly)
        XCTAssertFalse(harness.policy.networkImportsAllowed)
        XCTAssertFalse(harness.policy.filesystemAbsoluteImportsAllowed)
        XCTAssertFalse(harness.policy.symlinkEscapeAllowed)
        XCTAssertFalse(harness.policy.dynamicImportAvailableByDefault)
        XCTAssertEqual(harness.policy.dynamicImportScope, .blocked)
        XCTAssertTrue(harness.policy.dynamicImportGeneratedBundleOnly)
        XCTAssertTrue(harness.policy.dynamicImportStringLiteralLocalOnly)
        XCTAssertFalse(harness.policy.dynamicImportAvailable)
        XCTAssertFalse(harness.policy.moduleWorkerImportAvailable)
        XCTAssertEqual(harness.snapshot.importScriptsResolvedCount, 1)
        XCTAssertEqual(
            harness.snapshot.importedScripts.map(\.resolvedRelativePath),
            ["dependency.js"]
        )
        XCTAssertEqual(
            harness.snapshot.capturedListeners.first?.listenerSourceFile,
            "dependency.js"
        )
        XCTAssertEqual(
            result.responsePayload,
            .object(["fromImport": .string("dependency")])
        )
        XCTAssertEqual(result.resultKind, .delivered)
    }

    func testMultipleImportScriptsArgumentsExecuteInDeterministicOrder()
        throws
    {
        let fixture = try makeHarness(
            source: """
            globalThis.order = [];
            importScripts('first.js', 'second.js');
            chrome.runtime.onMessage.addListener(() => order.join(','));
            """,
            extraFiles: [
                "first.js": "order.push('first');",
                "second.js": "order.push('second');",
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(
            harness.snapshot.importedScripts.compactMap(\.evaluationOrder),
            [1, 2]
        )
        XCTAssertEqual(
            harness.snapshot.importedScripts.compactMap(\.resolvedRelativePath),
            ["first.js", "second.js"]
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "ordered import"
            ).responsePayload,
            .string("first,second")
        )
    }

    func testImportedRuntimeOnConnectListenerReceivesPortDispatch() throws {
        let fixture = try makeHarness(
            source: "importScripts('connect.js');\n",
            extraFiles: [
                "connect.js": """
                chrome.runtime.onConnect.addListener((port) => {
                  port.onMessage.addListener((message) => {
                    port.postMessage({ fromImport: message.value });
                  });
                });
                """,
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        let connected = harness.connectRuntime(name: "imported")
        let portID = try XCTUnwrap(connected.portID)
        let port = harness.deliverPortMessage(
            portID: portID,
            message: .object(["value": .string("port")])
        )

        XCTAssertEqual(connected.resultKind, .delivered)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnConnect))
        XCTAssertEqual(
            port?.postedMessages,
            [.object(["fromImport": .string("port")])]
        )
    }

    func testUnsafeImportScriptsFormsAreDiagnosedPrecisely() throws {
        let cases: [(String, ChromeMV3ServiceWorkerJSImportScriptsBlocker)] = [
            ("importScripts('missing.js');", .importedScriptMissing),
            ("importScripts('../outside.js');", .importPathTraversalRejected),
            ("importScripts('/Users/example/outside.js');", .absoluteFilesystemPathRejected),
            ("importScripts('https://example.com/remote.js');", .remoteURLRejected),
            ("importScripts('data:text/javascript,0');", .dataURLRejected),
            ("importScripts('blob:https://example.com/id');", .blobURLRejected),
            ("importScripts('file:///tmp/worker.js');", .fileURLRejected),
        ]

        for (source, blocker) in cases {
            let fixture = try makeHarness(
                source: source,
                localExperimentalGateAllowed: true
            )
            let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
                request: fixture.request()
            )

            XCTAssertEqual(harness.start().status, .failed, source)
            XCTAssertTrue(
                harness.snapshot.importScriptsBlockers.contains(blocker),
                source
            )
        }
    }

    func testSymlinkEscapeAndNonUTF8ImportScriptsAreDiagnosed() throws {
        let symlinkFixture = try makeHarness(
            source: "importScripts('linked.js');",
            localExperimentalGateAllowed: true
        )
        let outside = try temporaryDirectory()
            .appendingPathComponent("outside.js")
        try "chrome.runtime.onMessage.addListener(() => 'outside');"
            .write(to: outside, atomically: true, encoding: .utf8)
        let linked = symlinkFixture.generatedRootURL
            .appendingPathComponent("linked.js")
        try FileManager.default.createSymbolicLink(
            at: linked,
            withDestinationURL: outside
        )
        var symlinkRecord = symlinkFixture.generatedRecord
        symlinkRecord.copiedResourcePaths.append("linked.js")
        let symlinkHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: symlinkFixture.request(generatedRecord: symlinkRecord)
        )

        XCTAssertEqual(symlinkHarness.start().status, .failed)
        XCTAssertTrue(
            symlinkHarness.snapshot.importScriptsBlockers.contains(
                .importedScriptSymbolicLinkRejected
            )
        )

        let invalidFixture = try makeHarness(
            source: "importScripts('bad.js');",
            localExperimentalGateAllowed: true
        )
        try Data([0xff, 0xfe, 0xfd]).write(
            to: invalidFixture.generatedRootURL
                .appendingPathComponent("bad.js")
        )
        var invalidRecord = invalidFixture.generatedRecord
        invalidRecord.copiedResourcePaths.append("bad.js")
        let invalidHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: invalidFixture.request(generatedRecord: invalidRecord)
        )

        XCTAssertEqual(invalidHarness.start().status, .failed)
        XCTAssertTrue(
            invalidHarness.snapshot.importScriptsBlockers.contains(
                .importedScriptUTF8Required
            )
        )
    }

    func testLocalGeneratedBundleDynamicImportIsPreciselyBlockedUntilSupported()
        throws
    {
        let fixture = try makeHarness(
            source: """
            import('./dependency.js').then((module) => {
              globalThis.dynamicValue = module.value;
            });
            chrome.runtime.onMessage.addListener(() => globalThis.dynamicValue || 'pending');
            """,
            extraFiles: [
                "dependency.js": "export const value = 'dependency';",
            ],
            localExperimentalGateAllowed: true
        )
        let probe = ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
            .evaluate()
        var generatedRecord = fixture.generatedRecord
        if generatedRecord.copiedResourcePaths.contains("dependency.js")
            == false
        {
            generatedRecord.copiedResourcePaths.append("dependency.js")
        }
        let generatedDependency = fixture.generatedRootURL
            .appendingPathComponent("dependency.js")
        if FileManager.default.fileExists(atPath: generatedDependency.path)
            == false
        {
            try "export const value = 'dependency';".write(
                to: generatedDependency,
                atomically: true,
                encoding: .utf8
            )
        }
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(generatedRecord: generatedRecord)
        )
        let started = harness.start()

        if probe.dynamicImportAvailableInLocalExperimentalGate {
            XCTAssertEqual(started.status, .running)
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.isEmpty
                    == true
            )
        } else {
            XCTAssertEqual(started.status, .blocked)
            let record = try XCTUnwrap(
                harness.snapshot.resourceLoad?.dynamicImportRecords.first
            )
            XCTAssertEqual(record.requestPath, "./dependency.js")
            XCTAssertEqual(record.resolvedRelativePath, "dependency.js")
            XCTAssertTrue(record.generatedBundlePathValidated)
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.contains(
                    .dynamicImportLowerLevelAPINotAvailable
                ) == true
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.contains(
                    .dynamicImportResolverHookUnavailable
                ) == true
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.contains(
                    .dynamicImportGeneratedRootContainmentUnproven
                ) == true
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.blockers.contains(
                    .dynamicImportLowerLevelAPINotAvailable
                ) == true
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.blockers.contains(
                    .dynamicImportResolverHookUnavailable
                ) == true
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.blockers.contains(
                    .dynamicImportGeneratedRootContainmentUnproven
                ) == true
            )
        }
    }

    func testUnsafeDynamicImportFormsAreDiagnosedPrecisely() throws {
        let cases: [(String, ChromeMV3ServiceWorkerJSDynamicImportBlocker)] = [
            ("import('missing.js');", .importedModuleMissing),
            ("import('../outside.js');", .importPathTraversalRejected),
            ("import('/Users/example/outside.js');", .absoluteFilesystemPathRejected),
            ("import('https://example.com/remote.js');", .remoteURLRejected),
            ("import('data:text/javascript,0');", .dataURLRejected),
            ("import('blob:https://example.com/id');", .blobURLRejected),
            ("import('file:///tmp/worker.js');", .fileURLRejected),
            ("const path = './dependency.js'; import(path);", .dynamicImportArgumentNonString),
            ("import('./missing.js'); const path = './dependency.js'; import(path);", .dynamicImportArgumentNonString),
        ]

        for (source, blocker) in cases {
            let fixture = try makeHarness(
                source: source,
                localExperimentalGateAllowed: true
            )
            let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
                request: fixture.request()
            )

            XCTAssertEqual(harness.start().status, .blocked, source)
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.contains(
                    blocker
                ) == true,
                source
            )
        }
    }

    func testSymlinkEscapeAndNonUTF8DynamicImportsAreDiagnosed() throws {
        let symlinkFixture = try makeHarness(
            source: "import('linked.js');",
            localExperimentalGateAllowed: true
        )
        let outside = try temporaryDirectory()
            .appendingPathComponent("outside-module.js")
        try "export const value = 'outside';"
            .write(to: outside, atomically: true, encoding: .utf8)
        let linked = symlinkFixture.generatedRootURL
            .appendingPathComponent("linked.js")
        try FileManager.default.createSymbolicLink(
            at: linked,
            withDestinationURL: outside
        )
        var symlinkRecord = symlinkFixture.generatedRecord
        symlinkRecord.copiedResourcePaths.append("linked.js")
        let symlinkHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: symlinkFixture.request(generatedRecord: symlinkRecord)
        )

        XCTAssertEqual(symlinkHarness.start().status, .blocked)
        XCTAssertTrue(
            symlinkHarness.snapshot.resourceLoad?.dynamicImportBlockers
                .contains(.importedModuleSymbolicLinkRejected) == true
        )

        let invalidFixture = try makeHarness(
            source: "import('bad.js');",
            localExperimentalGateAllowed: true
        )
        try Data([0xff, 0xfe, 0xfd]).write(
            to: invalidFixture.generatedRootURL
                .appendingPathComponent("bad.js")
        )
        var invalidRecord = invalidFixture.generatedRecord
        invalidRecord.copiedResourcePaths.append("bad.js")
        let invalidHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: invalidFixture.request(generatedRecord: invalidRecord)
        )

        XCTAssertEqual(invalidHarness.start().status, .blocked)
        XCTAssertTrue(
            invalidHarness.snapshot.resourceLoad?.dynamicImportBlockers
                .contains(.importedModuleUTF8Required) == true
        )
    }

    func testCircularImportScriptsBlockedAndDuplicateImportsReevaluate()
        throws
    {
        let circular = try makeHarness(
            source: "importScripts('loop.js');",
            extraFiles: [
                "loop.js": "importScripts('loop.js');",
            ],
            localExperimentalGateAllowed: true
        )
        let circularHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: circular.request()
        )
        XCTAssertEqual(circularHarness.start().status, .failed)
        XCTAssertTrue(
            circularHarness.snapshot.importScriptsBlockers.contains(
                .circularImportBlocked
            )
        )

        let duplicate = try makeHarness(
            source: """
            globalThis.count = 0;
            importScripts('increment.js', 'increment.js');
            chrome.runtime.onMessage.addListener(() => count);
            """,
            extraFiles: [
                "increment.js": "count += 1;",
            ],
            localExperimentalGateAllowed: true
        )
        let duplicateHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: duplicate.request()
        )

        XCTAssertEqual(duplicateHarness.start().status, .running)
        XCTAssertEqual(duplicateHarness.snapshot.importScriptsResolvedCount, 2)
        XCTAssertEqual(
            duplicateHarness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "duplicate import"
            ).responsePayload,
            .number(2)
        )
    }

    func testClassicWorkerCapturesRegistrationAndDispatchesSendResponse() throws {
        let fixture = try makeHarness(
            source: """
            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
              sendResponse({ echo: message.value, urlRedacted: sender.urlRedacted });
            });
            chrome.storage.onChanged.addListener(() => {});
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        let started = harness.start()
        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["value": .string("captured")])],
            payloadSummary: "popup runtime.sendMessage"
        )

        XCTAssertEqual(started.status, .running)
        XCTAssertEqual(started.executionSurface, .javaScriptCore)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnMessage))
        XCTAssertTrue(harness.capturedListener(for: .storageOnChanged))
        XCTAssertEqual(harness.snapshot.capturedListeners.first?.registrationOrder, 1)
        XCTAssertEqual(harness.snapshot.capturedListeners.first?.listenerArity, 3)
        XCTAssertEqual(
            result.responsePayload,
            .object([
                "echo": .string("captured"),
                "urlRedacted": .bool(true),
            ])
        )
        XCTAssertEqual(result.resultKind, .delivered)
        XCTAssertEqual(result.lifecycleRoutingRecord?.resultKind, .delivered)
    }

    func testMessageNoReceiverPromiseAndListenerErrorAreDeterministic() throws {
        let noListener = try startedHarness(source: "")
        let noReceiver = noListener.dispatch(
            source: .contentScriptRuntimeMessage,
            arguments: [.object(["ping": .bool(true)])],
            payloadSummary: "content-script runtime.sendMessage"
        )
        XCTAssertEqual(noReceiver.resultKind, .noReceiver)

        let promise = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener(async () => 'later');\n"
        )
        let promiseResult = promise.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "Promise response"
        )
        XCTAssertEqual(promiseResult.resultKind, .unsupportedListenerMode)
        XCTAssertTrue(
            promiseResult.lastErrorMessage?.contains("observable but deferred")
                == true
        )

        let timedOut = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener((_m, _s, _r) => true);\n"
        )
        XCTAssertEqual(
            timedOut.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "open sendResponse channel"
            ).resultKind,
            .sendResponseTimeoutDiagnostic
        )

        let failing = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener(() => { throw new Error('listener failed'); });\n"
        )
        let failure = failing.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "throwing listener"
        )
        XCTAssertEqual(failure.resultKind, .listenerError)
        XCTAssertEqual(failure.lastErrorMessage, "listener failed")
    }

    func testRuntimeConnectPortMessageDeliveryDisconnectAndKeepaliveRelease()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              port.onMessage.addListener((message) => {
                port.postMessage({ echo: message.value, name: port.name });
              });
              port.onDisconnect.addListener(() => {});
            });
            """
        )

        let connected = harness.connectRuntime(name: "fixture-channel")
        let portID = try XCTUnwrap(connected.portID)
        let delivered = harness.deliverPortMessage(
            portID: portID,
            message: .object(["value": .string("port-value")])
        )

        XCTAssertEqual(connected.resultKind, .delivered)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnConnect))
        XCTAssertEqual(delivered?.onMessageListenerCount, 1)
        XCTAssertEqual(delivered?.onDisconnectListenerCount, 1)
        XCTAssertEqual(
            delivered?.postedMessages,
            [
                .object([
                    "echo": .string("port-value"),
                    "name": .string("fixture-channel"),
                ]),
            ]
        )
        XCTAssertEqual(
            harness.snapshot.lifecycleSnapshot?.activeKeepaliveRecords.count,
            1
        )
        XCTAssertTrue(harness.disconnectPort(portID: portID))
        XCTAssertEqual(harness.snapshot.ports.first?.connected, false)
        XCTAssertEqual(
            harness.snapshot.lifecycleSnapshot?.activeKeepaliveRecords.count,
            0
        )
    }

    func testStoragePermissionsAlarmContextMenuAndWebNavigationDispatch()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.storage.onChanged.addListener(() => {});
            chrome.permissions.onAdded.addListener(() => {});
            chrome.permissions.onRemoved.addListener(() => {});
            chrome.alarms.onAlarm.addListener(() => {});
            chrome.contextMenus.onClicked.addListener(() => {});
            chrome.webNavigation.onCommitted.addListener(() => {});
            """
        )
        let sources: [ChromeMV3ServiceWorkerEventSource] = [
            .storageChanged,
            .permissionsAdded,
            .permissionsRemoved,
            .alarmTriggered,
            .contextMenuClicked,
            .webNavigationSyntheticEvent,
        ]

        for source in sources {
            let result = harness.dispatch(
                source: source,
                arguments: [.object(["fixture": .bool(true)])],
                payloadSummary: source.rawValue
            )
            XCTAssertEqual(result.resultKind, .delivered, source.rawValue)
            XCTAssertEqual(
                result.lifecycleRoutingRecord?.resultKind,
                .delivered,
                source.rawValue
            )
        }
    }

    func testTrustedNativeFixturePortRequiresPolicyRoutesAndRevokes() throws {
        let harness = try startedHarness(source: "")
        let denied = harness.openTrustedNativeFixturePort(
            name: "com.sumi.fixture",
            trustedFixturePolicyAllowed: false
        )
        XCTAssertEqual(denied.resultKind, .blockedByPermission)

        let opened = harness.openTrustedNativeFixturePort(
            name: "com.sumi.fixture",
            trustedFixturePolicyAllowed: true
        )
        let portID = try XCTUnwrap(opened.portID)
        let delivered = harness.deliverTrustedNativeFixturePortMessage(
            portID: portID,
            message: .object(["fixture": .string("native")])
        )
        XCTAssertEqual(opened.resultKind, .delivered)
        XCTAssertEqual(delivered.resultKind, .delivered)
        XCTAssertEqual(
            delivered.lifecycleRoutingRecord?.resultKind,
            .delivered
        )

        harness.revokeTrustedNativeFixturePolicy()
        XCTAssertEqual(harness.snapshot.ports.first?.connected, false)
        XCTAssertEqual(
            harness.snapshot.ports.first?.disconnectReason,
            "trustedNativeFixturePolicyRevoked"
        )
    }

    func testExplicitLifecycleTeardownReleasesHarnessAndPorts() throws {
        let idle = try startedHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n"
        )
        _ = idle.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "idle eligible"
        )
        _ = idle.triggerIdleRelease()
        XCTAssertEqual(idle.snapshot.startRecord.status, .stoppedAfterIdle)

        let hardTimeout = try startedHarness(
            source: "chrome.runtime.onConnect.addListener(() => {});\n"
        )
        _ = hardTimeout.connectRuntime(name: "hard-timeout")
        _ = hardTimeout.triggerHardTimeout()
        XCTAssertEqual(
            hardTimeout.snapshot.startRecord.status,
            .stoppedAfterHardTimeout
        )
        XCTAssertEqual(hardTimeout.snapshot.ports.first?.connected, false)

        let disabled = try startedHarness(source: "")
        disabled.tearDownForExtensionDisable()
        XCTAssertEqual(disabled.snapshot.startRecord.status, .stoppedAfterDisable)

        let uninstalled = try startedHarness(source: "")
        uninstalled.tearDownForExtensionUninstall()
        XCTAssertEqual(
            uninstalled.snapshot.startRecord.status,
            .stoppedAfterUninstall
        )

        let profileClosed = try startedHarness(source: "")
        profileClosed.tearDownForProfileClose()
        XCTAssertEqual(
            profileClosed.snapshot.startRecord.status,
            .stoppedAfterProfileClose
        )

        let reset = try startedHarness(source: "")
        reset.reset()
        XCTAssertEqual(reset.snapshot.startRecord.status, .stoppedAfterReset)
        XCTAssertTrue(reset.snapshot.ports.isEmpty)
    }

    func testPolicyKeepsPermanentRuntimeSchedulersAndHostLaunchBlocked() {
        let policy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .enabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: true,
            generatedBundleRecordAvailable: true
        )

        XCTAssertFalse(policy.serviceWorkerJSExecutionAvailableByDefault)
        XCTAssertFalse(policy.permanentBackgroundAvailable)
        XCTAssertFalse(policy.timersAllowed)
        XCTAssertFalse(policy.pollingAllowed)
    }

    private func startedHarness(
        source: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixture = try makeHarness(
            source: source,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        XCTAssertEqual(harness.start().status, .running)
        return harness
    }

    private struct HarnessFixture {
        var manifest: ChromeMV3Manifest
        var generatedRecord: ChromeMV3GeneratedBundleRecord
        var generatedRootURL: URL
        var localExperimentalGateAllowed: Bool

        func request(
            manifest: ChromeMV3Manifest? = nil,
            generatedRecord: ChromeMV3GeneratedBundleRecord? = nil,
            moduleState: ChromeMV3ProfileHostModuleState = .enabled,
            extensionEnabled: Bool = true
        ) -> ChromeMV3ServiceWorkerJSExecutionRequest {
            ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: manifest ?? self.manifest,
                generatedBundleRecord: generatedRecord ?? self.generatedRecord,
                extensionID: "service-worker-js-fixture-extension",
                profileID: "service-worker-js-fixture-profile",
                moduleState: moduleState,
                extensionEnabled: extensionEnabled,
                localExperimentalGateAllowed:
                    localExperimentalGateAllowed
            )
        }
    }

    private func makeHarness(
        source: String,
        extraFiles: [String: String] = [:],
        serviceWorkerType: String? = nil,
        localExperimentalGateAllowed: Bool = false
    ) throws -> HarnessFixture {
        let fixtureDirectory = try temporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        var background: [String: Any] = [
            "service_worker": "background.js",
        ]
        if let serviceWorkerType {
            background["type"] = serviceWorkerType
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Service Worker JS Execution Fixture",
            "version": "1.0.0",
            "background": background,
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: fixtureDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try source.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        for (path, contents) in extraFiles {
            let url = fixtureDirectory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let storeRoot = try temporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot
        ).stageUnpackedDirectory(at: fixtureDirectory)
        let generated = try ChromeMV3GeneratedBundleWriter(
            rootURL: storeRoot
        ).writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        return HarnessFixture(
            manifest: stage.manifestSnapshot.normalizedManifest,
            generatedRecord: generated.record,
            generatedRootURL: generated.generatedBundleRootURL,
            localExperimentalGateAllowed: localExperimentalGateAllowed
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(url)
        return url
    }

}
