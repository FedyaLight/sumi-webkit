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

    func testDebugRaindropServiceWorkerHarnessDiagnostics() throws {
        let raindropRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/raindrop",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: raindropRoot.appendingPathComponent("manifest.json").path
            ),
            "Local Raindrop package is not available."
        )

        let storeRoot = try temporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot
        ).stageUnpackedDirectory(at: raindropRoot)
        let generated = try ChromeMV3GeneratedBundleWriter(
            rootURL: storeRoot
        ).writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: stage.manifestSnapshot.normalizedManifest,
                generatedBundleRecord: generated.record,
                extensionID: "debug-raindrop-service-worker-extension",
                profileID: "debug-raindrop-service-worker-profile",
                moduleState: .enabled,
                extensionEnabled: true,
                localExperimentalGateAllowed: true,
                dynamicImportRewriteExperimentAllowed: true
            )
        )
        let start = harness.start()
        let exception = start.exceptionDetails
        let diagnostic = [
            "status=\(start.status.rawValue)",
            "blockers=\(start.blockers.map(\.rawValue).joined(separator: ","))",
            "capturedListeners=\(start.capturedListenerCount)",
            "lastError=\(safeDebugToken(start.lastErrorMessage ?? "none"))",
            "classification=\(exception?.classification.rawValue ?? "none")",
            "missingGlobal=\(safeDebugToken(exception?.inferredMissingGlobal ?? "none"))",
            "missingProperty=\(safeDebugToken(exception?.inferredMissingProperty ?? "none"))",
            "line=\(exception?.line.map(String.init) ?? "none")",
            "column=\(exception?.column.map(String.init) ?? "none")",
        ].joined(separator: " ")
        print("SumiRaindropServiceWorkerHarness \(diagnostic)")
        let attachment = XCTAttachment(
            string: "SumiRaindropServiceWorkerHarness \(diagnostic)"
        )
        attachment.name = "SumiRaindropServiceWorkerHarness-sanitized-diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertFalse(diagnostic.contains("token"))
        XCTAssertFalse(diagnostic.contains("password"))
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
            moduleDisabled.policy.timersAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.timersAvailableByDefault)
        XCTAssertFalse(moduleDisabled.policy.wallClockTimersAllowed)
        XCTAssertFalse(
            moduleDisabled.policy
                .runtimeLastErrorAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            moduleDisabled.policy.runtimeLastErrorAvailableByDefault
        )
        XCTAssertFalse(moduleDisabled.policy.runtimeLastErrorCallbackScoped)
        XCTAssertFalse(
            moduleDisabled.policy
                .workerNavigatorUserAgentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            moduleDisabled.policy.workerNavigatorUserAgentAvailableByDefault
        )
        XCTAssertNil(moduleDisabled.policy.workerNavigatorUserAgent)
        XCTAssertFalse(
            moduleDisabled.policy.workerNavigatorChromeCompatibilityTokenAvailable
        )
        XCTAssertFalse(
            moduleDisabled.policy.webCryptoAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.webCryptoAvailableByDefault)
        XCTAssertFalse(
            moduleDisabled.policy.i18nGetUILanguageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.i18nGetUILanguageAvailableByDefault)
        XCTAssertFalse(
            moduleDisabled.policy.i18nGetMessageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.i18nGetMessageAvailableByDefault)
        XCTAssertTrue(moduleDisabled.policy.i18nGeneratedBundleLocalesOnly)
        XCTAssertFalse(moduleDisabled.policy.i18nNetworkLocalesAllowed)
        XCTAssertFalse(
            moduleDisabled.policy.i18nFilesystemLocaleFallbackAllowed
        )
        XCTAssertFalse(
            moduleDisabled.policy.alarmsAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.alarmsAvailableByDefault)
        XCTAssertFalse(moduleDisabled.policy.wallClockAlarmSchedulingAllowed)
        XCTAssertFalse(moduleDisabled.policy.backgroundWakeAllowed)
        XCTAssertTrue(moduleDisabled.policy.explicitAlarmTriggerOnly)
        XCTAssertFalse(
            moduleDisabled.policy
                .workerGlobalEventTargetAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            moduleDisabled.policy.workerGlobalEventTargetAvailableByDefault
        )
        XCTAssertFalse(moduleDisabled.policy.workerGlobalWindowDocumentExposed)
        XCTAssertFalse(
            moduleDisabled.policy.fetchClassificationAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            moduleDisabled.policy.fetchAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.fetchAvailableByDefault)
        XCTAssertFalse(moduleDisabled.policy.networkFetchAllowed)
        XCTAssertFalse(moduleDisabled.policy.extensionLocalFetchAllowed)
        XCTAssertTrue(moduleDisabled.policy.generatedBundleOnly)
        XCTAssertFalse(moduleDisabled.policy.credentialsAllowed)
        XCTAssertFalse(moduleDisabled.policy.cacheAllowed)
        XCTAssertFalse(moduleDisabled.policy.fetchNetworkExecutionAllowed)
        XCTAssertFalse(moduleDisabled.policy.fetchExtensionLocalExecutionAllowed)
        XCTAssertFalse(moduleDisabled.policy.cryptoGetRandomValuesAvailable)
        XCTAssertFalse(moduleDisabled.policy.cryptoRandomUUIDAvailable)
        XCTAssertFalse(
            moduleDisabled.policy.subtleCryptoAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            extensionDisabled.policy.webCryptoAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(extensionDisabled.policy.webCryptoAvailableByDefault)
        XCTAssertFalse(
            moduleDisabled.policy.moduleWorkerReadinessProbe.probeExecuted
        )
        XCTAssertFalse(
            extensionDisabled.policy.dynamicImportCapabilityProbe.probeExecuted
        )
        XCTAssertFalse(
            extensionDisabled.policy.moduleWorkerReadinessProbe.probeExecuted
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
        XCTAssertFalse(harness.policy.timersAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.timersAvailableByDefault)
        XCTAssertFalse(harness.policy.wallClockTimersAllowed)
        XCTAssertFalse(harness.policy.timersAllowed)
        XCTAssertFalse(
            harness.policy.runtimeLastErrorAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.runtimeLastErrorAvailableByDefault)
        XCTAssertFalse(harness.policy.runtimeLastErrorCallbackScoped)
        XCTAssertFalse(
            harness.policy
                .workerNavigatorUserAgentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.workerNavigatorUserAgentAvailableByDefault)
        XCTAssertNil(harness.policy.workerNavigatorUserAgent)
        XCTAssertFalse(
            harness.policy.workerNavigatorChromeCompatibilityTokenAvailable
        )
        XCTAssertFalse(harness.policy.webCryptoAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.webCryptoAvailableByDefault)
        XCTAssertFalse(
            harness.policy.i18nGetUILanguageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.i18nGetUILanguageAvailableByDefault)
        XCTAssertFalse(
            harness.policy.i18nGetMessageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.i18nGetMessageAvailableByDefault)
        XCTAssertTrue(harness.policy.i18nGeneratedBundleLocalesOnly)
        XCTAssertFalse(harness.policy.i18nNetworkLocalesAllowed)
        XCTAssertFalse(harness.policy.i18nFilesystemLocaleFallbackAllowed)
        XCTAssertFalse(harness.policy.alarmsAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.alarmsAvailableByDefault)
        XCTAssertFalse(harness.policy.wallClockAlarmSchedulingAllowed)
        XCTAssertFalse(harness.policy.backgroundWakeAllowed)
        XCTAssertTrue(harness.policy.explicitAlarmTriggerOnly)
        XCTAssertFalse(
            harness.policy
                .workerGlobalEventTargetAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.workerGlobalEventTargetAvailableByDefault)
        XCTAssertFalse(harness.policy.workerGlobalWindowDocumentExposed)
        XCTAssertFalse(
            harness.policy.fetchClassificationAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.fetchAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.fetchAvailableByDefault)
        XCTAssertFalse(harness.policy.networkFetchAllowed)
        XCTAssertFalse(harness.policy.extensionLocalFetchAllowed)
        XCTAssertTrue(harness.policy.generatedBundleOnly)
        XCTAssertFalse(harness.policy.credentialsAllowed)
        XCTAssertFalse(harness.policy.cacheAllowed)
        XCTAssertFalse(harness.policy.fetchNetworkExecutionAllowed)
        XCTAssertFalse(harness.policy.fetchExtensionLocalExecutionAllowed)
        XCTAssertFalse(harness.policy.cryptoGetRandomValuesAvailable)
        XCTAssertFalse(harness.policy.cryptoRandomUUIDAvailable)
        XCTAssertFalse(
            harness.policy.subtleCryptoAvailableInLocalExperimentalGate
        )
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
        XCTAssertTrue(module.policy.moduleWorkerReadinessProbe.probeExecuted)
        XCTAssertTrue(
            module.policy.moduleWorkerReadinessProbe.blockers.contains(
                .sourceTextModuleLoaderUnavailable
            )
        )
        XCTAssertFalse(
            module.policy.moduleWorkerReadinessProbe
                .moduleWorkerExecutionAvailableInLocalExperimentalGate
        )

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

    func testStaticConcatenationImportScriptsResolvesInsideGeneratedRoot()
        throws
    {
        let fixture = try makeHarness(
            source: "importScripts('./' + 'dependency.js');\n",
            extraFiles: [
                "dependency.js":
                    "chrome.runtime.onMessage.addListener(() => 'concat');",
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(harness.snapshot.importScriptsResolvedCount, 1)
        XCTAssertEqual(
            harness.snapshot.importedScripts.first?.resolvedRelativePath,
            "dependency.js"
        )
    }

    func testRuntimeVariableImportScriptsIsBlockedEvenWhenValueIsLocal()
        throws
    {
        let fixture = try makeHarness(
            source: """
            const dependency = './dependency.js';
            importScripts(dependency);
            """,
            extraFiles: ["dependency.js": ""],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .failed)
        XCTAssertTrue(
            harness.snapshot.importScriptsBlockers.contains(
                .computedImportScriptsRuntimeVariableRejected
            )
        )
    }

    func testKnownConstantMapImportScriptsRequiresEveryCandidateContained()
        throws
    {
        let safeFixture = try makeHarness(
            source: """
            const dependencies = { first: './first.js', second: './second.js' };
            importScripts(dependencies.first);
            """,
            extraFiles: [
                "first.js": "",
                "second.js": "",
            ],
            localExperimentalGateAllowed: true
        )
        let safeHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: safeFixture.request()
        )
        XCTAssertEqual(
            safeHarness.start().status,
            .running,
            "\(safeHarness.snapshot)"
        )
        XCTAssertEqual(
            safeHarness.snapshot.importScriptsResolvedCount,
            1,
            "\(safeHarness.snapshot)"
        )

        let unsafeFixture = try makeHarness(
            source: """
            const dependencies = { first: './first.js', second: '../outside.js' };
            importScripts(dependencies.first);
            """,
            extraFiles: ["first.js": ""],
            localExperimentalGateAllowed: true
        )
        let unsafeHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: unsafeFixture.request()
        )
        XCTAssertEqual(unsafeHarness.start().status, .failed)
        XCTAssertTrue(
            unsafeHarness.snapshot.importScriptsBlockers.contains(
                .computedImportScriptsConstantMapCandidateUnsafe
            )
        )
    }

    func testWorkerGlobalCompatibilityLayerIsNarrowAndDeterministic()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onMessage.addListener(() => ({
              domName: new DOMException('blocked', 'InvalidStateError').name,
              navigatorName: navigator.appName,
              navigatorChromeFamily: navigator.userAgent.includes(' Chrome/0'),
              href: location.href,
              id: chrome.runtime.id,
              url: new URL('https://example.com/a?b=1').searchParams.get('b'),
              text: new TextDecoder().decode(new TextEncoder().encode('ok')),
              base64: atob(btoa('ok')),
              randomLength: crypto.getRandomValues(new Uint8Array(4)).length,
              randomUUIDValid: /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(crypto.randomUUID()),
              subtleType: typeof crypto.subtle,
              subtleDigestType: typeof crypto.subtle.digest,
              workerGlobalScopeType: typeof WorkerGlobalScope,
              serviceWorkerGlobalScopeType: typeof ServiceWorkerGlobalScope,
              workerInstance: self instanceof WorkerGlobalScope,
              getURL: chrome.runtime.getURL('dependency.js').startsWith('chrome-extension://service-worker-js-fixture-extension/'),
              manifestVersion: chrome.runtime.getManifest().manifest_version,
              browserType: typeof browser,
              windowType: typeof window,
              documentType: typeof document
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "safe worker globals"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "base64": .string("ok"),
                "browserType": .string("undefined"),
                "documentType": .string("undefined"),
                "domName": .string("InvalidStateError"),
                "getURL": .bool(true),
                "href": .string(
                    "chrome-extension://service-worker-js-fixture-extension/background.js"
                ),
                "id": .string("service-worker-js-fixture-extension"),
                "manifestVersion": .number(3),
                "navigatorName": .string("Netscape"),
                "navigatorChromeFamily": .bool(true),
                "randomLength": .number(4),
                "randomUUIDValid": .bool(true),
                "serviceWorkerGlobalScopeType": .string("function"),
                "subtleDigestType": .string("function"),
                "subtleType": .string("object"),
                "text": .string("ok"),
                "url": .string("1"),
                "workerGlobalScopeType": .string("function"),
                "workerInstance": .bool(true),
                "windowType": .string("undefined"),
            ])
        )
        XCTAssertTrue(harness.policy.webCryptoAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.webCryptoAvailableByDefault)
        XCTAssertTrue(
            harness.policy
                .workerNavigatorUserAgentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            harness.policy.workerNavigatorUserAgentAvailableByDefault
        )
        XCTAssertTrue(
            harness.policy.workerNavigatorChromeCompatibilityTokenAvailable
        )
        XCTAssertEqual(harness.policy.subtleCryptoSupportedMethods, ["digest"])
        XCTAssertTrue(
            harness.policy.subtleCryptoBlockedMethods.contains("importKey")
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "getRandomValues" && $0.status == "fulfilled"
            }
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "randomUUID" && $0.status == "fulfilled"
            }
        )
    }

    func testWebCryptoGetRandomValuesUsesSecureNonDummyRandomness() throws {
        let harness = try startedHarness(
            source: """
            const first = new Uint8Array(32);
            const second = new Uint8Array(32);
            crypto.getRandomValues(first);
            crypto.getRandomValues(second);
            chrome.runtime.onMessage.addListener(() => ({
              firstZero: first.every((value) => value === 0),
              secondZero: second.every((value) => value === 0),
              equal: first.every((value, index) => value === second[index])
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "secure random"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "equal": .bool(false),
                "firstZero": .bool(false),
                "secondZero": .bool(false),
            ])
        )
        XCTAssertEqual(
            harness.snapshot.cryptoOperationRecords.filter {
                $0.operation == "getRandomValues"
                    && $0.status == "fulfilled"
            }.count,
            2
        )
    }

    func testSubtleCryptoDigestSHA256WorksAndDoesNotRecordMaterial()
        throws
    {
        let harness = try startedHarness(
            source: """
            const hex = (buffer) => Array.from(new Uint8Array(buffer))
              .map((value) => value.toString(16).padStart(2, '0'))
              .join('');
            crypto.subtle.digest('SHA-256', new TextEncoder().encode('abc'))
              .then((buffer) => { globalThis.digestHex = hex(buffer); })
              .catch((error) => { globalThis.digestError = error.name; });
            chrome.runtime.onMessage.addListener(() => ({
              digestHex: globalThis.digestHex || null,
              digestError: globalThis.digestError || null
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "subtle digest"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "digestError": .null,
                "digestHex":
                    .string(
                        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                    ),
            ])
        )
        let record = try XCTUnwrap(
            harness.snapshot.cryptoOperationRecords.first {
                $0.operation == "subtle.digest"
            }
        )
        XCTAssertEqual(record.algorithm, "SHA-256")
        XCTAssertEqual(record.byteCount, 3)
        XCTAssertEqual(record.status, "fulfilled")
        let serializedRecords = String(
            data: try JSONEncoder().encode(
                harness.snapshot.cryptoOperationRecords
            ),
            encoding: .utf8
        )
        XCTAssertFalse(serializedRecords?.contains("abc") == true)
    }

    func testUnsupportedSubtleCryptoRejectsDeterministically() throws {
        let harness = try startedHarness(
            source: """
            crypto.subtle.digest('MD5', new Uint8Array([1, 2, 3]))
              .catch((error) => { globalThis.md5Error = `${error.name}:${error.message.includes('unsupported algorithm')}`; });
            crypto.subtle.importKey('raw', new Uint8Array([1, 2, 3]), { name: 'PBKDF2' }, false, ['deriveBits'])
              .catch((error) => { globalThis.importKeyError = `${error.name}:${error.message.includes('not supported')}`; });
            chrome.runtime.onMessage.addListener(() => ({
              md5Error: globalThis.md5Error || null,
              importKeyError: globalThis.importKeyError || null
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "unsupported subtle"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "importKeyError": .string("NotSupportedError:true"),
                "md5Error": .string("NotSupportedError:true"),
            ])
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "subtle.digest"
                    && $0.status == "blocked"
                    && $0.blocker == "unsupportedAlgorithm"
                    && $0.algorithm == "MD5"
            }
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "subtle.importKey"
                    && $0.status == "blocked"
                    && $0.blocker == "unsupportedMethod"
                    && $0.algorithm == "PBKDF2"
            }
        )
    }

    func testUnsupportedSubtleCryptoDoesNotLogKeyMaterial() throws {
        let harness = try startedHarness(
            source: """
            const keyMaterial = new Uint8Array([115, 101, 99, 114, 101, 116]);
            crypto.subtle.importKey('raw', keyMaterial, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
              .catch((error) => { globalThis.keyRejected = error.name; });
            chrome.runtime.onMessage.addListener(() => globalThis.keyRejected || 'pending');
            """
        )

        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "unsupported importKey key material"
            ).responsePayload,
            .string("NotSupportedError")
        )
        let serializedRecords = String(
            data: try JSONEncoder().encode(
                harness.snapshot.cryptoOperationRecords
            ),
            encoding: .utf8
        )
        XCTAssertFalse(serializedRecords?.contains("secret") == true)
        XCTAssertFalse(serializedRecords?.contains("115,101,99") == true)
    }

    func testBitwardenStyleWebCryptoConstructorAdvancesAndBlocksPrecisely()
        throws
    {
        let harness = try startedHarness(
            source: """
            class WebCryptoFunctionService {
              constructor(scope) {
                if (scope?.crypto?.subtle == null) {
                  throw new Error('Could not instantiate WebCryptoFunctionService. Could not locate Subtle crypto.');
                }
                this.crypto = scope.crypto;
                this.subtle = scope.crypto.subtle;
              }
              hash(value) {
                return this.subtle.digest({ name: 'SHA-256' }, new TextEncoder().encode(value))
                  .then((buffer) => Array.from(new Uint8Array(buffer))
                    .map((byte) => byte.toString(16).padStart(2, '0')).join(''));
              }
              pbkdf2() {
                return this.subtle.importKey('raw', new Uint8Array([1, 2, 3]), { name: 'PBKDF2' }, false, ['deriveBits']);
              }
            }
            const service = new WebCryptoFunctionService(globalThis);
            globalThis.constructorAdvanced = true;
            service.hash('abc').then((hex) => { globalThis.hashHex = hex; });
            service.pbkdf2().catch((error) => { globalThis.pbkdf2Blocked = `${error.name}:${error.message.includes('not supported')}`; });
            chrome.runtime.onMessage.addListener(() => ({
              constructorAdvanced: globalThis.constructorAdvanced === true,
              hashHex: globalThis.hashHex || null,
              pbkdf2Blocked: globalThis.pbkdf2Blocked || null
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "Bitwarden-style crypto"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "constructorAdvanced": .bool(true),
                "hashHex":
                    .string(
                        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                    ),
                "pbkdf2Blocked": .string("NotSupportedError:true"),
            ])
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "subtle.digest"
                    && $0.algorithm == "SHA-256"
                    && $0.status == "fulfilled"
            }
        )
        XCTAssertTrue(
            harness.snapshot.cryptoOperationRecords.contains {
                $0.operation == "subtle.importKey"
                    && $0.algorithm == "PBKDF2"
                    && $0.blocker == "unsupportedMethod"
            }
        )
    }

    func testWorkerGlobalScopeAvoidsProtonStyleWindowFallback() throws {
        let harness = try startedHarness(
            source: """
            const target = typeof WorkerGlobalScope !== 'undefined' && self instanceof WorkerGlobalScope ? self : window;
            chrome.runtime.onMessage.addListener(() => ({
              targetIsSelf: target === self,
              windowType: typeof window,
              documentType: typeof document
            }));
            """
        )

        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "Proton worker global fallback"
            ).responsePayload,
            .object([
                "documentType": .string("undefined"),
                "targetIsSelf": .bool(true),
                "windowType": .string("undefined"),
            ])
        )
    }

    func testChromeI18nGetUILanguageIsDeterministicAndNarrow() throws {
        let harness = try startedHarness(
            source: """
            const uiLanguage = chrome.i18n.getUILanguage();
            const getMessageType = typeof chrome.i18n.getMessage;
            const getMessageResult = chrome.i18n.getMessage('appName');
            chrome.runtime.onMessage.addListener(() => ({
              uiLanguage,
              getMessageType,
              getMessageResult,
              windowType: typeof window,
              documentType: typeof document
            }));
            """,
            uiLanguageOverride: "fr_CA"
        )

        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "i18n getUILanguage"
            ).responsePayload,
            .object([
                "documentType": .string("undefined"),
                "getMessageResult": .string(""),
                "getMessageType": .string("function"),
                "uiLanguage": .string("fr-CA"),
                "windowType": .string("undefined"),
            ])
        )
        XCTAssertEqual(harness.policy.i18nSelectedUILanguage, "fr-CA")
        XCTAssertEqual(harness.policy.i18nSelectedUILanguageSource, "testOverride")
        XCTAssertTrue(
            harness.policy.i18nGetUILanguageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.i18nGetUILanguageAvailableByDefault)
        XCTAssertTrue(
            harness.policy.i18nGetMessageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.i18nGetMessageAvailableByDefault)
        XCTAssertTrue(harness.policy.i18nGeneratedBundleLocalesOnly)
        XCTAssertFalse(harness.policy.i18nNetworkLocalesAllowed)
        XCTAssertFalse(harness.policy.i18nFilesystemLocaleFallbackAllowed)
        XCTAssertTrue(
            harness.snapshot.i18nOperationRecords.contains {
                $0.operation == "chrome.i18n.getUILanguage"
                    && $0.status == "fulfilled"
                    && $0.value == "fr-CA"
            }
        )
        XCTAssertTrue(
            harness.snapshot.i18nOperationRecords.contains {
                $0.operation == "chrome.i18n.getMessage"
                    && $0.status == "missing"
                    && $0.messageName == "appName"
                    && $0.value == ""
                    && $0.blocker == "missingMessage"
            }
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains(
                "chrome.i18n.getMessage"
            )
        )
    }

    func testChromeI18nGetMessageLoadsGeneratedBundleCatalogs()
        throws
    {
        let fixture = try makeHarness(
            source: """
            const appName = chrome.i18n.getMessage('appName', ['A', 'B'], { escapeLt: true });
            const fallbackOnly = chrome.i18n.getMessage('fallbackOnly');
            const direct = chrome.i18n.getMessage('arrayDirect', ['one', 'two']);
            const missing = chrome.i18n.getMessage('missingName');
            const extensionID = chrome.i18n.getMessage('@@extension_id');
            const uiLocale = chrome.i18n.getMessage('@@ui_locale');
            const bidiDir = chrome.i18n.getMessage('@@bidi_dir');
            const tooMany = chrome.i18n.getMessage(
              'appName',
              ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
            );
            chrome.runtime.onMessage.addListener(() => ({
              appName,
              fallbackOnly,
              direct,
              missing,
              extensionID,
              uiLocale,
              bidiDir,
              tooManyType: typeof tooMany
            }));
            """,
            extraFiles: [
                "_locales/en/messages.json": """
                {
                  "fallbackOnly": { "message": "Fallback text" },
                  "appName": {
                    "message": "Hello $1 and $TWO$ $$ <x>",
                    "placeholders": {
                      "two": { "content": "$2" }
                    }
                  }
                }
                """,
                "_locales/fr/messages.json": """
                {
                  "appName": {
                    "message": "Bonjour $1 et $TWO$ $$ <x>",
                    "placeholders": {
                      "two": { "content": "$2" }
                    }
                  },
                  "arrayDirect": {
                    "message": "Direct $1 $2 $3"
                  }
                }
                """,
            ],
            manifestAdditions: ["default_locale": "en"],
            localExperimentalGateAllowed: true
        )
        XCTAssertTrue(
            fixture.generatedRecord.copiedResourcePaths.contains(
                "_locales/en/messages.json"
            )
        )
        XCTAssertTrue(
            fixture.generatedRecord.copiedResourcePaths.contains(
                "_locales/fr/messages.json"
            )
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(uiLanguageOverride: "fr_CA")
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertTrue(harness.policy.i18nGetMessageAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.i18nGetMessageAvailableByDefault)
        XCTAssertEqual(harness.policy.i18nDefaultLocale, "en")
        XCTAssertEqual(harness.policy.i18nSelectedLocale, "fr_CA")
        XCTAssertEqual(harness.policy.i18nFallbackLocale, "en")
        XCTAssertEqual(harness.policy.i18nLocaleLookupOrder, ["fr_CA", "fr", "en"])
        XCTAssertEqual(harness.policy.i18nAvailableLocales, ["en", "fr"])
        XCTAssertEqual(harness.policy.i18nMissingCatalogLocales, ["fr_CA"])
        XCTAssertTrue(harness.policy.i18nGeneratedBundleLocalesOnly)
        XCTAssertFalse(harness.policy.i18nNetworkLocalesAllowed)
        XCTAssertFalse(harness.policy.i18nFilesystemLocaleFallbackAllowed)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "i18n getMessage"
            ).responsePayload,
            .object([
                "appName": .string("Bonjour A et B $ &lt;x>"),
                "bidiDir": .string("ltr"),
                "direct": .string("Direct one two "),
                "extensionID": .string("service-worker-js-fixture-extension"),
                "fallbackOnly": .string("Fallback text"),
                "missing": .string(""),
                "tooManyType": .string("undefined"),
                "uiLocale": .string("fr_CA"),
            ])
        )
        XCTAssertTrue(
            harness.snapshot.i18nOperationRecords.contains {
                $0.operation == "chrome.i18n.getMessage"
                    && $0.status == "fulfilled"
                    && $0.messageName == "appName"
                    && $0.source == "fr"
            }
        )
        XCTAssertTrue(
            harness.snapshot.i18nOperationRecords.contains {
                $0.operation == "chrome.i18n.getMessage"
                    && $0.status == "missing"
                    && $0.messageName == "missingName"
                    && $0.value == ""
            }
        )
        XCTAssertTrue(
            harness.snapshot.i18nOperationRecords.contains {
                $0.operation == "chrome.i18n.getMessage"
                    && $0.status == "blocked"
                    && $0.messageName == "appName"
                    && $0.blocker == "tooManySubstitutions"
            }
        )
        XCTAssertTrue(
            harness.snapshot.blockedUnsupportedCalls.contains(
                "chrome.i18n.getMessage"
            )
        )
    }

    func testChromeI18nGetMessageBlocksUnsafeInvalidAndSymlinkCatalogs()
        throws
    {
        let fixture = try makeHarness(
            source: """
            const value = chrome.i18n.getMessage('safe');
            chrome.runtime.onMessage.addListener(() => value);
            """,
            extraFiles: [
                "_locales/en/messages.json": """
                { "safe": { "message": "safe" } }
                """,
            ],
            manifestAdditions: ["default_locale": "en"],
            localExperimentalGateAllowed: true
        )
        var record = fixture.generatedRecord
        let invalidJSON = fixture.generatedRootURL
            .appendingPathComponent("_locales/fr/messages.json")
        try FileManager.default.createDirectory(
            at: invalidJSON.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{".write(to: invalidJSON, atomically: true, encoding: .utf8)
        let outside = try temporaryDirectory()
            .appendingPathComponent("messages.json")
        try "{ \"outside\": { \"message\": \"outside\" } }".write(
            to: outside,
            atomically: true,
            encoding: .utf8
        )
        let symlink = fixture.generatedRootURL
            .appendingPathComponent("_locales/es/messages.json")
        try FileManager.default.createDirectory(
            at: symlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: outside
        )
        record.copiedResourcePaths.append(contentsOf: [
            "_locales/en/../messages.json",
            "_locales/es/messages.json",
            "_locales/fr/messages.json",
        ])
        record.copiedResourcePaths.sort()

        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(generatedRecord: record)
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "i18n unsafe catalogs"
            ).responsePayload,
            .string("safe")
        )
        XCTAssertTrue(
            harness.policy.i18nInvalidCatalogPaths.contains(
                "_locales/en/../messages.json"
            )
        )
        XCTAssertTrue(
            harness.policy.i18nInvalidCatalogPaths.contains(
                "_locales/es/messages.json"
            )
        )
        XCTAssertTrue(
            harness.policy.i18nInvalidCatalogPaths.contains(
                "_locales/fr/messages.json"
            )
        )
        XCTAssertTrue(
            harness.policy.i18nGetMessageBlockers.contains(
                "invalidLocaleCatalogBlocked"
            )
        )
    }

    func testChromeAlarmsCreateGetReplaceAndExplicitOnAlarmDispatch() throws {
        let harness = try startedHarness(
            source: """
            globalThis.alarmState = { onAlarmName: null, callbackName: null, missingType: null };
            chrome.alarms.create('sync', {
              delayInMinutes: 1,
              periodInMinutes: 5
            }, () => {
              globalThis.alarmState.createLastError =
                chrome.runtime.lastError ? chrome.runtime.lastError.message : null;
            });
            chrome.alarms.create('sync', {
              when: 42000,
              periodInMinutes: 10
            });
            chrome.alarms.get('sync', (alarm) => {
              globalThis.alarmState.callbackName = alarm && alarm.name;
              globalThis.alarmState.callbackScheduledTime = alarm && alarm.scheduledTime;
              globalThis.alarmState.callbackPeriod = alarm && alarm.periodInMinutes;
              globalThis.alarmState.callbackLastError =
                chrome.runtime.lastError ? chrome.runtime.lastError.message : null;
            });
            chrome.alarms.get('missing').then((alarm) => {
              globalThis.alarmState.missingType = typeof alarm;
            });
            chrome.alarms.onAlarm.addListener((alarm) => {
              globalThis.alarmState.onAlarmName = alarm.name;
              globalThis.alarmState.onAlarmScheduledTime = alarm.scheduledTime;
              globalThis.alarmState.onAlarmPeriod = alarm.periodInMinutes;
            });
            chrome.runtime.onMessage.addListener(() => globalThis.alarmState);
            """
        )

        XCTAssertTrue(harness.policy.alarmsAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.alarmsAvailableByDefault)
        XCTAssertFalse(harness.policy.wallClockAlarmSchedulingAllowed)
        XCTAssertFalse(harness.policy.backgroundWakeAllowed)
        XCTAssertTrue(harness.policy.explicitAlarmTriggerOnly)
        XCTAssertFalse(harness.policy.pollingAllowed)
        XCTAssertEqual(harness.snapshot.alarmRecords.count, 1)
        let record = try XCTUnwrap(harness.snapshot.alarmRecords.first)
        XCTAssertEqual(record.name, "sync")
        XCTAssertEqual(record.scheduledTime, 42000)
        XCTAssertNil(record.delayInMinutes)
        XCTAssertEqual(record.periodInMinutes, 10)
        XCTAssertTrue(record.replacedExistingAlarm)
        XCTAssertTrue(
            record.diagnostics.contains {
                $0.contains("No wall-clock scheduler")
            }
        )
        XCTAssertTrue(
            harness.snapshot.alarmOperationRecords.contains {
                $0.methodName == "create"
                    && $0.succeeded
                    && $0.alarmName == "sync"
            }
        )
        XCTAssertTrue(
            harness.snapshot.alarmOperationRecords.contains {
                $0.methodName == "get"
                    && $0.succeeded
                    && $0.alarmName == "missing"
            }
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0 == "chrome.alarms.create" || $0 == "chrome.alarms.get"
            }
        )
        XCTAssertTrue(harness.snapshot.timers.isEmpty)
        XCTAssertTrue(harness.snapshot.timerDrainRecords.isEmpty)

        let alarmDispatch = harness.triggerAlarm(name: "sync")
        XCTAssertEqual(alarmDispatch.source, .alarmTriggered)
        XCTAssertEqual(alarmDispatch.event, .alarmsOnAlarm)
        XCTAssertEqual(alarmDispatch.resultKind, .delivered)

        let state = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "read alarm state"
        )
        XCTAssertEqual(
            state.responsePayload,
            .object([
                "callbackLastError": .null,
                "callbackName": .string("sync"),
                "callbackPeriod": .number(10),
                "callbackScheduledTime": .number(42000),
                "createLastError": .null,
                "missingType": .string("undefined"),
                "onAlarmName": .string("sync"),
                "onAlarmPeriod": .number(10),
                "onAlarmScheduledTime": .number(42000),
            ])
        )
    }

    func testChromeAlarmsDefaultNameMissingGetClearAndInvalidOptions()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.alarmState = {};
            chrome.alarms.create({ delayInMinutes: 2 });
            chrome.alarms.get((alarm) => {
              globalThis.alarmState.defaultName = alarm && alarm.name;
              globalThis.alarmState.defaultDelay = alarm && alarm.delayInMinutes;
            });
            chrome.alarms.get('missing', (alarm) => {
              globalThis.alarmState.missingCallbackType = typeof alarm;
            });
            chrome.alarms.clear('', (cleared) => {
              globalThis.alarmState.defaultCleared = cleared;
            });
            chrome.alarms.clear('missing').then((cleared) => {
              globalThis.alarmState.missingCleared = cleared;
            });
            chrome.alarms.create('bad-both', {
              when: 1,
              delayInMinutes: 1
            }).catch((error) => {
              globalThis.alarmState.invalidBoth = error.message;
            });
            chrome.alarms.create('bad-negative', {
              delayInMinutes: -1
            }, () => {
              globalThis.alarmState.invalidLastError =
                chrome.runtime.lastError && chrome.runtime.lastError.message;
            }).catch((error) => {
              globalThis.alarmState.invalidNegative = error.message;
            });
            chrome.runtime.onMessage.addListener(() => globalThis.alarmState);
            """
        )

        XCTAssertTrue(harness.snapshot.alarmRecords.isEmpty)
        XCTAssertTrue(
            harness.snapshot.alarmOperationRecords.contains {
                $0.methodName == "clear"
                    && $0.succeeded
                    && $0.alarmName == ""
                    && $0.resultPayload == .bool(true)
            }
        )
        XCTAssertTrue(
            harness.snapshot.alarmOperationRecords.contains {
                $0.methodName == "clear"
                    && $0.succeeded
                    && $0.alarmName == "missing"
                    && $0.resultPayload == .bool(false)
            }
        )
        XCTAssertEqual(
            harness.snapshot.alarmOperationRecords.filter {
                $0.succeeded == false
            }.count,
            2
        )

        let state = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "read invalid alarm state"
        )
        guard case .object(let object) = state.responsePayload else {
            XCTFail("Expected alarm state object.")
            return
        }
        XCTAssertEqual(object["defaultName"], .string(""))
        XCTAssertEqual(object["defaultDelay"], .number(2))
        XCTAssertEqual(object["missingCallbackType"], .string("undefined"))
        XCTAssertEqual(object["defaultCleared"], .bool(true))
        XCTAssertEqual(object["missingCleared"], .bool(false))
        XCTAssertEqual(
            object["invalidBoth"],
            .string(
                "alarms.create accepts either when or delayInMinutes, not both."
            )
        )
        XCTAssertEqual(
            object["invalidNegative"],
            .string("alarms.create delayInMinutes must be non-negative.")
        )
        XCTAssertEqual(
            object["invalidLastError"],
            .string("alarms.create delayInMinutes must be non-negative.")
        )
    }

    func testWorkerGlobalEventTargetIsNonDOMAndObservable() throws {
        let harness = try startedHarness(
            source: """
            let count = 0;
            let onceCount = 0;
            const seen = [];
            const listener = (event) => {
              count += 1;
              seen.push(`${event.type}:${event.target === self}:${event.currentTarget === self}`);
              event.preventDefault();
            };
            const onceListener = { handleEvent() { onceCount += 1; } };
            addEventListener('message', listener);
            const firstResult = dispatchEvent({ type: 'message', cancelable: true });
            removeEventListener('message', listener);
            const secondResult = dispatchEvent({ type: 'message', cancelable: true });
            addEventListener('install', onceListener, { once: true });
            const firstOnce = dispatchEvent({ type: 'install' });
            const secondOnce = dispatchEvent({ type: 'install' });
            chrome.runtime.onMessage.addListener(() => ({
              count,
              onceCount,
              seen: seen.join(','),
              firstResult,
              secondResult,
              firstOnce,
              secondOnce,
              addType: typeof addEventListener,
              removeType: typeof removeEventListener,
              dispatchType: typeof dispatchEvent,
              windowType: typeof window,
              documentType: typeof document
            }));
            """
        )

        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "worker global event target"
            ).responsePayload,
            .object([
                "addType": .string("function"),
                "count": .number(1),
                "dispatchType": .string("function"),
                "documentType": .string("undefined"),
                "firstOnce": .bool(true),
                "firstResult": .bool(false),
                "onceCount": .number(1),
                "removeType": .string("function"),
                "secondOnce": .bool(true),
                "secondResult": .bool(true),
                "seen": .string("message:true:true"),
                "windowType": .string("undefined"),
            ])
        )
        XCTAssertTrue(
            harness.policy
                .workerGlobalEventTargetAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.workerGlobalEventTargetAvailableByDefault)
        XCTAssertFalse(harness.policy.workerGlobalWindowDocumentExposed)
        XCTAssertTrue(
            harness.policy.workerGlobalEventTargetSupportedTypes
                .contains("message")
        )
        XCTAssertTrue(
            harness.snapshot.workerGlobalEventRecords.contains {
                $0.operation == .addEventListener
                    && $0.eventType == "message"
                    && $0.listenerCount == 1
                    && $0.blocked == false
            }
        )
        XCTAssertTrue(
            harness.snapshot.workerGlobalEventRecords.contains {
                $0.operation == .dispatchEvent
                    && $0.eventType == "message"
                    && $0.dispatchListenerCount == 1
                    && $0.defaultPrevented
            }
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.contains("window") || $0.contains("document")
            }
        )
    }

    func testChromeRuntimeIDSurvivesWebExtensionPolyfillWrapping() throws {
        let harness = try startedHarness(
            source: """
            const wrapWebExtensionPolyfillStyle = (chromeGlobal) => {
              if (!(globalThis.chrome && globalThis.chrome.runtime && globalThis.chrome.runtime.id)) {
                throw new Error('This script should only be loaded in a browser extension.');
              }
              if (globalThis.browser && globalThis.browser.runtime && globalThis.browser.runtime.id) {
                return globalThis.browser;
              }
              const wrapNamespace = (source, metadata = {}) => {
                const cache = Object.create(null);
                return new Proxy(Object.create(source), {
                  has(_target, property) {
                    return property in source || property in cache;
                  },
                  get(_target, property) {
                    if (property in cache) return cache[property];
                    if (!(property in source)) return undefined;
                    const value = source[property];
                    if (value && typeof value === 'object') {
                      cache[property] = wrapNamespace(value, metadata[property] || {});
                      return cache[property];
                    }
                    return value;
                  }
                });
              };
              return wrapNamespace(chromeGlobal, {
                runtime: {
                  requestUpdateCheck: { minArgs: 0, maxArgs: 0 }
                }
              });
            };
            const rp = wrapWebExtensionPolyfillStyle(globalThis.chrome);
            chrome.runtime.onMessage.addListener(() => ({
              browserType: typeof browser,
              extensionID: rp.runtime?.id?.split(' ')[0]
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "webextension polyfill runtime id"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "browserType": .string("undefined"),
                "extensionID": .string(
                    "service-worker-js-fixture-extension"
                ),
            ])
        )
    }

    func testStandardExtensionEventNamespacesAreCapturedNarrowly() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onInstalled.addListener(() => {});
            chrome.runtime.onMessageExternal.addListener(() => {});
            chrome.runtime.onStartup.addListener(() => {});
            chrome.runtime.onUpdateAvailable.addListener(() => {});
            chrome.tabs.onActivated.addListener(() => {});
            chrome.tabs.onUpdated.addListener(() => {});
            chrome.tabs.onRemoved.addListener(() => {});
            chrome.commands.onCommand.addListener(() => {});
            chrome.webRequest.onAuthRequired.addListener(() => {});
            chrome.webRequest.onCompleted.addListener(() => {});
            """
        )
        let captured = Set(harness.snapshot.capturedListeners.map(\.event))

        XCTAssertTrue(captured.contains(.runtimeOnInstalled))
        XCTAssertTrue(captured.contains(.runtimeOnMessageExternal))
        XCTAssertTrue(captured.contains(.runtimeOnStartup))
        XCTAssertTrue(captured.contains(.runtimeOnUpdateAvailable))
        XCTAssertTrue(captured.contains(.tabsOnActivated))
        XCTAssertTrue(captured.contains(.tabsOnUpdated))
        XCTAssertTrue(captured.contains(.tabsOnRemoved))
        XCTAssertTrue(captured.contains(.commandsOnCommand))
        XCTAssertTrue(captured.contains(.webRequestOnAuthRequired))
        XCTAssertTrue(captured.contains(.webRequestOnCompleted))
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.hasPrefix("chrome.")
            }
        )
    }

    func testTabsOnActivatedEventObjectSupportsRemoveAndHasListener() throws {
        let harness = try startedHarness(
            source: """
            function retained(activeInfo) {}
            function removed(activeInfo) {}
            chrome.tabs.onActivated.addListener(retained);
            chrome.tabs.onActivated.addListener(removed);
            const hadRemoved = chrome.tabs.onActivated.hasListener(removed);
            chrome.tabs.onActivated.removeListener(removed);
            const hasRemoved = chrome.tabs.onActivated.hasListener(removed);
            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
                sendResponse({ hadRemoved, hasRemoved });
            });
            """
        )
        let captured = Set(harness.snapshot.capturedListeners.map(\.event))

        XCTAssertTrue(captured.contains(.tabsOnActivated))
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.hasPrefix("chrome.tabs.onActivated")
            }
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object([:])],
            payloadSummary: "tabs.onActivated listener state"
        )

        XCTAssertEqual(
            result.responsePayload,
            .object([
                "hadRemoved": .bool(true),
                "hasRemoved": .bool(false),
            ])
        )
    }

    func testRuntimeInstalledEventDispatchesDetailsAndExportsStorage()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onInstalled.addListener((details) => {
              globalThis.installReason = details.reason;
              chrome.storage.local.set({
                lifecycleReady: true,
                lifecycleReason: details.reason
              });
            });
            """
        )

        XCTAssertTrue(
            harness.importStorageValues(
                ["existing": .string("kept")],
                area: .local
            )
        )
        let dispatch = harness.dispatch(
            source: .runtimeInstalled,
            arguments: [
                .object(["reason": .string("install")]),
            ],
            payloadSummary: "runtime.onInstalled reason=install"
        )
        let exported = try XCTUnwrap(
            harness.exportStorageValues(area: .local)
        )

        XCTAssertEqual(dispatch.event, .runtimeOnInstalled)
        XCTAssertEqual(dispatch.source, .runtimeInstalled)
        XCTAssertEqual(dispatch.resultKind, .delivered)
        XCTAssertEqual(
            dispatch.lifecycleRoutingRecord?.wakeResult?.reason,
            .installOrUpdateEvent
        )
        XCTAssertEqual(
            dispatch.lifecycleRoutingRecord?.wakeResult?.listenerEvent,
            .runtimeOnInstalled
        )
        XCTAssertEqual(exported["existing"], .string("kept"))
        XCTAssertEqual(exported["lifecycleReady"], .bool(true))
        XCTAssertEqual(exported["lifecycleReason"], .string("install"))
        XCTAssertEqual(
            harness.snapshot.dispatchRecords.filter {
                $0.event == .runtimeOnInstalled
            }.count,
            1
        )
        XCTAssertEqual(
            harness.snapshot.storageOperationRecords.filter {
                $0.area == "local" && $0.operation == "set"
            }.count,
            1
        )
    }

    func testGeneratedBundleLocalFetchReturnsMinimalResponse() throws {
        var fixture = try makeHarness(
            source: """
            globalThis.fetchResult = { state: 'pending' };
            Promise.all([
              fetch(chrome.runtime.getURL('local.json')).then(async (response) => {
                const clone = response.clone();
                const parsed = await clone.json();
                const text = await response.text();
                return {
                  ok: response.ok,
                  status: response.status,
                  statusText: response.statusText,
                  urlPrefix: response.url.startsWith('chrome-extension://service-worker-js-fixture-extension/'),
                  text,
                  parsed: parsed.value,
                  contentType: response.headers.get('content-type'),
                  bodyUsed: response.bodyUsed
                };
              }),
              fetch('./bytes.txt').then(async (response) => ({
                byteLength: (await response.arrayBuffer()).byteLength
              })),
              fetch('/local.json', { method: 'HEAD' }).then(async (response) => ({
                headTextLength: (await response.text()).length
              }))
            ]).then((values) => {
              globalThis.fetchResult = {
                first: values[0],
                byteLength: values[1].byteLength,
                headTextLength: values[2].headTextLength,
                requestType: typeof Request,
                headersType: typeof Headers,
                responseType: typeof Response,
                windowType: typeof window,
                documentType: typeof document
              };
            }).catch((error) => {
              globalThis.fetchResult = { error: String(error && error.message ? error.message : error) };
            });
            chrome.runtime.onMessage.addListener(() => globalThis.fetchResult);
            """,
            localExperimentalGateAllowed: true
        )
        fixture.generatedRecord = try generatedRecord(
            fixture,
            adding: [
                "bytes.txt": "abcde",
                "local.json": #"{"value":"local"}"#,
            ]
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "local fetch"
            ).responsePayload,
            .object([
                "byteLength": .number(5),
                "documentType": .string("undefined"),
                "first": .object([
                    "bodyUsed": .bool(true),
                    "contentType": .string("application/json; charset=utf-8"),
                    "ok": .bool(true),
                    "parsed": .string("local"),
                    "status": .number(200),
                    "statusText": .string("OK"),
                    "text": .string(#"{"value":"local"}"#),
                    "urlPrefix": .bool(true),
                ]),
                "headersType": .string("function"),
                "headTextLength": .number(0),
                "requestType": .string("function"),
                "responseType": .string("function"),
                "windowType": .string("undefined"),
            ])
        )
        XCTAssertEqual(harness.snapshot.fetchClassificationRecords.count, 3)
        XCTAssertTrue(
            harness.snapshot.fetchClassificationRecords.contains {
                $0.requestKind == .extensionLocalGeneratedResource
                    && $0.executionAllowed
                    && $0.fetchedResourcePath == "local.json"
                    && $0.status == 200
                    && $0.sourceByteCount == #"{"value":"local"}"#.utf8.count
            }
        )
        XCTAssertTrue(
            harness.snapshot.fetchClassificationRecords.contains {
                $0.requestKind == .relativeGeneratedResource
                    && $0.executionAllowed
                    && $0.fetchedResourcePath == "bytes.txt"
                    && $0.sourceByteCount == 5
            }
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.hasPrefix("globalThis.fetch")
            }
        )
    }

    func testUnsafeAndNonLocalFetchesRemainBlockedAndClassified() throws {
        let harness = try startedHarness(
            source: """
            const ignored = (promise) => promise.catch(() => {});
            ignored(fetch('https://example.com/data.json'));
            ignored(fetch('data:text/plain,blocked'));
            ignored(fetch('blob:https://example.com/blocked'));
            ignored(fetch('file:///tmp/blocked.json'));
            ignored(fetch('../outside.json'));
            ignored(fetch('/Users/example/outside.json'));
            ignored(fetch('./missing.json'));
            ignored(fetch('./local.json', { credentials: 'include' }));
            ignored(fetch('./local.json', { cache: 'reload' }));
            ignored(fetch('./local.json', { method: 'POST' }));
            chrome.runtime.onMessage.addListener(() => 'after-fetch');
            """,
            extraFiles: ["local.json": "{}"]
        )

        XCTAssertEqual(harness.snapshot.fetchClassificationRecords.count, 10)
        let records = harness.snapshot.fetchClassificationRecords
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .remoteNetworkBlocked
                    && $0.networkAccessRequired
                    && $0.blocker == "networkFetchDisabled"
                    && $0.executionAllowed == false
            }
        )
        XCTAssertTrue(records.contains { $0.requestKind == .dataURLBlocked })
        XCTAssertTrue(records.contains { $0.requestKind == .blobURLBlocked })
        XCTAssertTrue(records.contains { $0.requestKind == .fileURLBlocked })
        XCTAssertTrue(records.contains { $0.requestKind == .traversalBlocked })
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .absoluteFilesystemBlocked
                    && $0.blocker == "absoluteFilesystemFetchBlocked"
            }
        )
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .missingResource
                    && $0.blocker == "notCopiedGeneratedResource"
            }
        )
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .unsupportedRequestShape
                    && $0.blocker == "credentialsUnsupported"
            }
        )
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .unsupportedRequestShape
                    && $0.blocker == "cacheUnsupported"
            }
        )
        XCTAssertTrue(
            records.contains {
                $0.requestKind == .unsupportedRequestShape
                    && $0.blocker == "methodUnsupported"
            }
        )
        XCTAssertTrue(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.hasPrefix("globalThis.fetch.remoteNetworkBlocked")
            }
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "after blocked fetch"
            ).responsePayload,
            .string("after-fetch")
        )
    }

    func testGeneratedBundleWasmFetchReturnsBinaryArrayBuffer() throws {
        var fixture = try makeHarness(
            source: """
            globalThis.fetchResult = { state: 'pending' };
            fetch(chrome.runtime.getURL('module.wasm')).then(async (response) => {
              const bytes = new Uint8Array(await response.arrayBuffer());
              globalThis.fetchResult = {
                contentType: response.headers.get('content-type'),
                byteLength: bytes.byteLength,
                magic: Array.from(bytes.slice(0, 4)).join(',')
              };
            }).catch((error) => {
              globalThis.fetchResult = { error: String(error && error.message ? error.message : error) };
            });
            chrome.runtime.onMessage.addListener(() => globalThis.fetchResult);
            """,
            localExperimentalGateAllowed: true
        )
        fixture.generatedRecord = try generatedRecord(
            fixture,
            addingBinary: [
                "module.wasm": Data(
                    [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
                ),
            ]
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "wasm fetch"
            ).responsePayload,
            .object([
                "byteLength": .number(8),
                "contentType": .string("application/wasm"),
                "magic": .string("0,97,115,109"),
            ])
        )
        XCTAssertTrue(
            harness.snapshot.fetchClassificationRecords.contains {
                $0.executionAllowed
                    && $0.fetchedResourcePath == "module.wasm"
                    && $0.sourceByteCount == 8
            }
        )
    }

    func testFetchRejectsSymlinkGeneratedBundleResource() throws {
        let fixture = try makeHarness(
            source: """
            fetch('./linked.json').catch(() => {});
            chrome.runtime.onMessage.addListener(() => 'after-fetch');
            """,
            localExperimentalGateAllowed: true
        )
        let outside = try temporaryDirectory()
            .appendingPathComponent("outside.json")
        try #"{"outside":true}"#.write(
            to: outside,
            atomically: true,
            encoding: .utf8
        )
        let linked = fixture.generatedRootURL
            .appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(
            at: linked,
            withDestinationURL: outside
        )
        var record = fixture.generatedRecord
        record.copiedResourcePaths.append("linked.json")
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(generatedRecord: record)
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertTrue(
            harness.snapshot.fetchClassificationRecords.contains {
                $0.requestKind == .symlinkEscapeBlocked
                    && $0.fetchedResourcePath == "linked.json"
                    && $0.executionAllowed == false
                    && $0.blocker == "symlinkEscapeBlocked"
            }
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "after blocked fetch"
            ).responsePayload,
            .string("after-fetch")
        )
    }

    func testProtonStyleMissingGlobalFailureIsClassified() throws {
        let fixture = try makeHarness(
            source: """
            const i = () => undefined;
            var g = 'DOMException', b = i(g), w = b.prototype;
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        let started = harness.start()

        XCTAssertEqual(started.status, .failed)
        XCTAssertEqual(
            started.exceptionDetails?.classification,
            .missingStandardWorkerGlobal
        )
        XCTAssertEqual(started.exceptionDetails?.inferredMissingGlobal, "DOMException")
        XCTAssertEqual(started.exceptionDetails?.inferredMissingProperty, "prototype")
        XCTAssertNotNil(started.exceptionDetails?.line)
        XCTAssertNotNil(started.exceptionDetails?.column)
        XCTAssertTrue(started.exceptionDetails?.stack?.isEmpty == false)
    }

    func testSubtleCryptoFailureIsClassifiedWithoutImplementingSubtle() throws {
        let fixture = try makeHarness(
            source: """
            throw new Error('Could not instantiate WebCryptoFunctionService. Could not locate Subtle crypto.');
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        let started = harness.start()

        XCTAssertEqual(started.status, .failed)
        XCTAssertEqual(started.exceptionDetails?.classification, .missingWebAPI)
        XCTAssertEqual(
            started.exceptionDetails?.inferredMissingGlobal,
            "SubtleCrypto"
        )
        XCTAssertEqual(
            started.exceptionDetails?.inferredMissingProperty,
            "crypto.subtle"
        )
    }

    func testBitwardenStyleNullDeviceReceiverIsClassifiedConservatively()
        throws
    {
        let fixture = try makeHarness(
            source: """
            class ApiService {
              constructor(platformUtilsService) {
                this.device = platformUtilsService.getDevice();
                this.deviceType = this.device.toString();
              }
            }
            new ApiService({ getDevice: () => null });
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        let started = harness.start()
        let receiver = try XCTUnwrap(
            started.exceptionDetails?.nullishReceiverDetails
        )

        XCTAssertEqual(started.status, .failed)
        XCTAssertEqual(
            started.exceptionDetails?.classification,
            .bundlerRuntimeAssumption
        )
        XCTAssertEqual(
            started.exceptionDetails?.inferredMissingProperty,
            "this.device.toString"
        )
        XCTAssertEqual(receiver.receiverPath, "this.device")
        XCTAssertEqual(receiver.accessedProperty, "toString")
        XCTAssertEqual(receiver.receiverValue, .nullValue)
        XCTAssertTrue(
            receiver.receiverObjectSummary.contains(
                "not the concrete this receiver object"
            )
        )
        XCTAssertTrue(started.exceptionDetails?.precedingChromeAPICalls.isEmpty == true)
        XCTAssertTrue(
            started.exceptionDetails?.precedingStorageOperations.isEmpty == true
        )
    }

    func testWindowGlobalFailureIsClassifiedWithoutImplementingWindow()
        throws
    {
        let fixture = try makeHarness(
            source: """
            window.addEventListener('message', () => {});
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        let started = harness.start()

        XCTAssertEqual(started.status, .failed)
        XCTAssertEqual(started.exceptionDetails?.classification, .missingWebAPI)
        XCTAssertEqual(started.exceptionDetails?.inferredMissingGlobal, "window")
    }

    func testWebpackBoundedComputedImportScriptsResolvesGeneratedChunk()
        throws
    {
        let fixture = try makeHarness(
            source: """
            var o = {};
            var loaded = {};
            o.p = '';
            o.u = e => e + '.background.js';
            o.f = {};
            o.f.i = (t) => { loaded[t] || importScripts(o.p + o.u(t)); };
            o.e = (t) => { o.f.i(t); return Promise.resolve(); };
            o.e(719);
            chrome.runtime.onMessage.addListener(() => globalThis.webpackLoaded);
            """,
            extraFiles: [
                "719.background.js":
                    "globalThis.webpackLoaded = 'bounded';",
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(harness.snapshot.importScriptsResolvedCount, 1)
        XCTAssertEqual(
            harness.snapshot.importedScripts.first?.resolvedRelativePath,
            "719.background.js"
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "webpack bounded chunk"
            ).responsePayload,
            .string("bounded")
        )
    }

    func testWebpackComputedImportScriptsCanResolveSameExtensionURL()
        throws
    {
        let fixture = try makeHarness(
            source: """
            var o = {};
            var loaded = {};
            o.p = chrome.runtime.getURL('');
            o.u = e => e + '.background.js';
            o.f = {};
            o.f.i = (t) => { loaded[t] || importScripts(o.p + o.u(t)); };
            o.e = (t) => { o.f.i(t); return Promise.resolve(); };
            o.e(719);
            chrome.runtime.onMessage.addListener(() => globalThis.webpackLoaded);
            """,
            extraFiles: [
                "719.background.js":
                    "globalThis.webpackLoaded = 'same-extension-url';",
            ],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(
            harness.snapshot.importedScripts.first?.requestPath,
            "chrome-extension://service-worker-js-fixture-extension/719.background.js"
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "webpack extension URL chunk"
            ).responsePayload,
            .string("same-extension-url")
        )
    }

    func testWebpackComputedImportScriptsWithoutLiteralChunkSetStaysBlocked()
        throws
    {
        let fixture = try makeHarness(
            source: """
            var o = {};
            o.p = '';
            o.u = e => e + '.background.js';
            o.f = {};
            o.f.i = (t) => importScripts(o.p + o.u(t));
            o.f.i(719);
            """,
            extraFiles: ["719.background.js": ""],
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .failed)
        XCTAssertTrue(
            harness.snapshot.importScriptsBlockers.contains(
                .computedImportScriptsRuntimeVariableRejected
            )
        )
    }

    func testMethodNamedImportDoesNotTriggerDynamicImportBlocker() throws {
        let fixture = try makeHarness(
            source: """
            class Loader { import(e, t) { return e || t; } }
            const loader = new Loader();
            chrome.runtime.onMessage.addListener(() => loader.import('method', 'fallback'));
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .running)
        XCTAssertEqual(harness.snapshot.resourceLoad?.dynamicImportDetected, false)
        XCTAssertEqual(harness.snapshot.resourceLoad?.dynamicImportRecords, [])
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "method named import"
            ).responsePayload,
            .string("method")
        )
    }

    func testBoundedAsyncFlushObservesPromiseContinuationBeforeMirror() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener(async (port) => {
              await Promise.resolve();
              chrome.storage.local.set({ asyncFlushMarker: "ready" });
              port.postMessage({ ready: true });
            });
            """
        )
        _ = harness.connectRuntime(name: "async-flush")
        let flush = harness.flushBoundedAsyncContinuations(
            maxDrainPasses: 8,
            maxElapsedMilliseconds: 50
        )
        XCTAssertTrue(flush.attempted)
        XCTAssertGreaterThan(flush.storageSetOperationCountAfterFlush, 0)
        XCTAssertEqual(
            harness.exportStorageValues(area: .local)?["asyncFlushMarker"],
            .string("ready")
        )
    }

    func testSessionMemoryPortGetResponseAppendsToInitializationOutbox() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              if (port.name !== "session") {
                return;
              }
              port.onMessage.addListener(async (message, replyPort) => {
                const target = replyPort || port;
                if (message && message.originator === "background") {
                  return;
                }
                let result = null;
                if (message.action === "get" || message.action === "has") {
                  result = await Promise.resolve(null);
                }
                target.postMessage({
                  originator: "background",
                  id: message.id,
                  key: message.key,
                  data: JSON.stringify(result)
                });
              });
              port.postMessage({
                originator: "background",
                action: "initialization",
                data: JSON.stringify([])
              });
            });
            """
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        let port = try XCTUnwrap(
            harness.deliverPortMessageFlushingAsyncContinuations(
                portID: portID,
                message: .object([
                    "originator": .string("foreground"),
                    "id": .string("probe-get-id"),
                    "key": .string("global_popupViewMemory_popup-view-cache"),
                    "action": .string("get"),
                ])
            )
        )
        XCTAssertEqual(port.postedMessages.count, 2)
        guard case .object(let response)? = port.postedMessages.last else {
            return XCTFail("Expected get response in cumulative Port outbox.")
        }
        XCTAssertEqual(response["originator"], .string("background"))
        XCTAssertEqual(response["id"], .string("probe-get-id"))
    }

    func testSessionMemoryPortGetResponseWithStorageCallbackAwait() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              if (port.name !== "session") {
                return;
              }
              port.onMessage.addListener(async (message) => {
                if (message && message.originator === "background") {
                  return;
                }
                let result = null;
                if (message.action === "get" || message.action === "has") {
                  result = await new Promise((resolve) => {
                    chrome.storage.local.get(message.key, (items) => {
                      resolve(items[message.key] ?? null);
                    });
                  });
                }
                port.postMessage({
                  originator: "background",
                  id: message.id,
                  key: message.key,
                  data: JSON.stringify(result)
                });
              });
              port.postMessage({
                originator: "background",
                action: "initialization",
                data: JSON.stringify([])
              });
            });
            """
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        let port = try XCTUnwrap(
            harness.deliverPortMessageFlushingAsyncContinuations(
                portID: portID,
                message: .object([
                    "originator": .string("foreground"),
                    "id": .string("storage-callback-get-id"),
                    "key": .string("global_popupViewMemory_popup-view-cache"),
                    "action": .string("get"),
                ])
            )
        )
        XCTAssertEqual(port.postedMessages.count, 2)
        guard case .object(let response)? = port.postedMessages.last else {
            return XCTFail("Expected storage-backed get response in Port outbox.")
        }
        XCTAssertEqual(response["originator"], .string("background"))
        XCTAssertEqual(response["id"], .string("storage-callback-get-id"))
        XCTAssertEqual(response["key"], .string("global_popupViewMemory_popup-view-cache"))
        XCTAssertEqual(response["data"], .string("null"))

        let trace = try XCTUnwrap(harness.finalizeMemorySessionGetTrace(portID: portID))
        XCTAssertEqual(trace.requestReceivedCategory, "received")
        XCTAssertEqual(trace.requestShapeCategory, "foregroundGet")
        XCTAssertEqual(trace.handlerMatchedCategory, "matched")
        XCTAssertEqual(trace.sessionGetStartedCategory, "started")
        XCTAssertEqual(trace.awaitedApiCategory, "chrome.storage.local.get")
        XCTAssertEqual(trace.storageCallbackCategory, "invoked")
        XCTAssertEqual(trace.getResolvedCategory, "resolved")
        XCTAssertEqual(trace.responseConstructedCategory, "constructed")
        XCTAssertEqual(trace.responsePostMessageCalledCategory, "called")
        XCTAssertEqual(trace.responseOutboxCapturedCategory, "captured")
    }

    func testSessionThenLocalMemoryPortGetResponseRequiresChainedMicrotaskDrain()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              if (port.name !== "session") {
                return;
              }
              port.onMessage.addListener(async (message) => {
                if (message && message.originator === "background") {
                  return;
                }
                let result = null;
                if (message.action === "get" || message.action === "has") {
                  await new Promise((resolve) => {
                    chrome.storage.session.get("session-key", (items) => {
                      resolve(items["session-key"] ?? null);
                    });
                  });
                  result = await new Promise((resolve) => {
                    const localKey = "session_" + message.key;
                    chrome.storage.local.get(localKey, (items) => {
                      resolve(items[localKey] ?? null);
                    });
                  });
                }
                port.postMessage({
                  originator: "background",
                  id: message.id,
                  key: message.key,
                  data: JSON.stringify(result)
                });
              });
              port.postMessage({
                originator: "background",
                action: "initialization",
                data: JSON.stringify([])
              });
            });
            """
        )
        XCTAssertTrue(
            harness.importStorageValues(
                ["session-key": .string("present")],
                area: .session
            )
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        let port = try XCTUnwrap(
            harness.deliverPortMessageFlushingAsyncContinuations(
                portID: portID,
                message: .object([
                    "originator": .string("foreground"),
                    "id": .string("session-local-chain-id"),
                    "key": .string("global_popupViewMemory_popup-view-cache"),
                    "action": .string("get"),
                ])
            )
        )
        XCTAssertEqual(port.postedMessages.count, 2)
        guard case .object(let response)? = port.postedMessages.last else {
            return XCTFail("Expected chained storage get response in Port outbox.")
        }
        XCTAssertEqual(response["originator"], .string("background"))
        XCTAssertEqual(response["id"], .string("session-local-chain-id"))

        let trace = try XCTUnwrap(harness.finalizeMemorySessionGetTrace(portID: portID))
        XCTAssertEqual(trace.awaitedApiCategory, "chrome.storage.session.get")
        XCTAssertEqual(trace.continuationAfterSessionGetCategory, "continued")
        XCTAssertEqual(trace.nextAwaitedApiCategory, "chrome.storage.local.get")
        XCTAssertEqual(trace.localGetStartedCategory, "started")
        XCTAssertEqual(trace.localGetCallbackCategory, "invoked")
        XCTAssertEqual(trace.localGetPromiseCategory, "resolved")
        XCTAssertEqual(trace.getResolvedCategory, "resolved")
        XCTAssertEqual(trace.responseConstructionReachedCategory, "reached")
        XCTAssertEqual(trace.responsePostMessageCalledCategory, "called")
        XCTAssertEqual(trace.responseOutboxCapturedCategory, "captured")
        XCTAssertEqual(trace.getPendingReasonCategory, "notObserved")
    }

    func testMemorySessionGetTraceClassifiesContinuationAfterSessionGetNotDrained()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              if (port.name !== "session") {
                return;
              }
              port.onMessage.addListener(async (message) => {
                if (message && message.originator === "background") {
                  return;
                }
                await new Promise((resolve) => {
                  chrome.storage.session.get("session-key", (items) => {
                    resolve(items["session-key"] ?? null);
                  });
                });
              });
              port.postMessage({
                originator: "background",
                action: "initialization",
                data: JSON.stringify([])
              });
            });
            """
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        _ = harness.deliverPortMessage(
            portID: portID,
            message: .object([
                "originator": .string("foreground"),
                "id": .string("stall-after-session-id"),
                "key": .string("global_popupViewMemory_popup-view-cache"),
                "action": .string("get"),
            ])
        )
        _ = harness.drainPendingStorageCallbacks()
        let trace = try XCTUnwrap(harness.finalizeMemorySessionGetTrace(portID: portID))
        XCTAssertEqual(trace.storageCallbackCategory, "invoked")
        XCTAssertEqual(trace.storagePromiseCategory, "resolved")
        XCTAssertEqual(trace.getResolvedCategory, "notResolved")
        XCTAssertEqual(
            trace.getPendingReasonCategory,
            "continuationAfterSessionGetNotDrained"
        )
        XCTAssertNotEqual(
            trace.getPendingReasonCategory,
            "viewCachePromiseContinuationNotDrained"
        )
    }

    func testInitializationShapedPortMessageDoesNotSatisfyMemorySessionGetTrace()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              if (port.name !== "session") {
                return;
              }
              port.postMessage({
                originator: "background",
                action: "initialization",
                data: JSON.stringify([])
              });
            });
            """
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        let trace = try XCTUnwrap(harness.finalizeMemorySessionGetTrace(portID: portID))
        XCTAssertEqual(trace.requestReceivedCategory, "notReceived")
        XCTAssertEqual(trace.responseOutboxCapturedCategory, "notCaptured")
        XCTAssertEqual(trace.getPendingReasonCategory, "notObserved")
        XCTAssertEqual(
            harness.snapshot.ports.first { $0.portID == portID }?.postedMessages.count,
            1
        )
    }

    func testAsyncPortOnMessageResponseDeliveredAfterBoundedFlush() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              port.onMessage.addListener(async (message) => {
                await Promise.resolve();
                port.postMessage({
                  originator: 'background',
                  id: message.id,
                  key: message.key,
                  data: JSON.stringify(null)
                });
              });
            });
            """
        )
        let connect = harness.connectRuntime(
            name: "session",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: nil,
                frameID: nil,
                documentID: nil,
                sourceURL: "chrome-extension://test-extension-id/",
                urlRedacted: false,
                redactionState: "harness sender"
            )
        )
        let portID = try XCTUnwrap(connect.portID)
        let port = try XCTUnwrap(
            harness.deliverPortMessageFlushingAsyncContinuations(
                portID: portID,
                message: .object([
                    "originator": .string("foreground"),
                    "id": .string("probe-get-id"),
                    "key": .string("global_popupViewMemory_popup-view-cache"),
                    "action": .string("get"),
                ])
            )
        )
        XCTAssertEqual(port.postedMessages.count, 1)
        guard case .object(let response)? = port.postedMessages.first else {
            return XCTFail("Expected one Port response object")
        }
        XCTAssertEqual(response["originator"], .string("background"))
        XCTAssertEqual(response["id"], .string("probe-get-id"))
    }

    func testDeterministicTimerShimQueuesDrainsCancelsAndTicksManually()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.callbackLog = [];
            setTimeout((value) => callbackLog.push(value), 10, 'timeout');
            const cancelledTimeout = setTimeout(() => callbackLog.push('cancelled-timeout'), 10);
            clearTimeout(cancelledTimeout);
            setInterval(() => callbackLog.push('interval'), 20);
            const cancelledInterval = setInterval(() => callbackLog.push('cancelled-interval'), 20);
            clearInterval(cancelledInterval);
            chrome.runtime.onMessage.addListener(() => callbackLog.join(','));
            """
        )

        XCTAssertTrue(harness.policy.timersAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.timersAvailableByDefault)
        XCTAssertFalse(harness.policy.wallClockTimersAllowed)
        XCTAssertFalse(harness.policy.pollingAllowed)
        XCTAssertEqual(harness.snapshot.timers.count, 2)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                arguments: [],
                payloadSummary: "before explicit timeout drain"
            ).responsePayload,
            .string("")
        )

        let drained = try XCTUnwrap(harness.drainQueuedTimeouts())
        XCTAssertEqual(drained.callbackCount, 1)
        XCTAssertEqual(drained.callbackErrors, [])
        XCTAssertEqual(drained.pendingTimeoutCount, 0)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                arguments: [],
                payloadSummary: "after explicit timeout drain"
            ).responsePayload,
            .string("timeout")
        )

        let ticked = try XCTUnwrap(harness.tickIntervals())
        XCTAssertEqual(ticked.callbackCount, 1)
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                arguments: [],
                payloadSummary: "after explicit interval tick"
            ).responsePayload,
            .string("timeout,interval")
        )
        XCTAssertEqual(harness.snapshot.timers.map(\.kind), [.interval])
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

    func testDynamicImportRewriteExperimentIsExplicitAndPolicyBlocked()
        throws
    {
        let fixture = try makeHarness(
            source: "import('./dependency.js');",
            localExperimentalGateAllowed: true
        )
        let defaultHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        XCTAssertEqual(defaultHarness.start().status, .blocked)
        XCTAssertFalse(
            defaultHarness.policy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            defaultHarness.snapshot.resourceLoad?
                .dynamicImportRewriteExperimentApplied == true
        )

        let rewriteFixture = try makeHarness(
            source: "import('./dependency.js');",
            localExperimentalGateAllowed: true,
            dynamicImportRewriteExperimentAllowed: true
        )
        let moduleDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: rewriteFixture.request(moduleState: .disabled)
        )
        let extensionDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: rewriteFixture.request(extensionEnabled: false)
        )

        XCTAssertEqual(moduleDisabled.start().status, .blocked)
        XCTAssertEqual(extensionDisabled.start().status, .blocked)
        XCTAssertNil(moduleDisabled.snapshot.resourceLoad)
        XCTAssertNil(extensionDisabled.snapshot.resourceLoad)
        XCTAssertFalse(
            moduleDisabled.policy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            extensionDisabled.policy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
    }

    func testDynamicImportRewriteExecutesGeneratedDependencyAndCapturesListener()
        throws
    {
        let fixture = try makeHarness(
            source: """
            import('./dependency.js').then(() => {
              chrome.runtime.onMessage.addListener((message) => {
                return { loaded: globalThis.dynamicDependencyValue, value: message.value };
              });
            });
            """,
            localExperimentalGateAllowed: true,
            dynamicImportRewriteExperimentAllowed: true
        )
        let generatedRecord = try generatedRecord(
            fixture,
            adding: [
                "dependency.js":
                    "globalThis.dynamicDependencyValue = 'dependency-loaded';",
            ]
        )
        let backgroundURL = fixture.generatedRootURL
            .appendingPathComponent("background.js")
        let backgroundBefore = try Data(contentsOf: backgroundURL)
        let dependencyURL = fixture.generatedRootURL
            .appendingPathComponent("dependency.js")
        let dependencyBefore = try Data(contentsOf: dependencyURL)
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(generatedRecord: generatedRecord)
        )

        let started = harness.start()
        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["value": .string("after-rewrite")])],
            payloadSummary: "rewritten dynamic import listener"
        )
        let resource = try XCTUnwrap(harness.snapshot.resourceLoad)

        XCTAssertEqual(started.status, .running)
        XCTAssertTrue(
            harness.policy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.dynamicImportAvailable)
        XCTAssertEqual(
            harness.policy.dynamicImportRewriteExperimentScope,
            .generatedBundleOnly
        )
        XCTAssertTrue(resource.dynamicImportRewriteExperimentApplied)
        XCTAssertEqual(resource.dynamicImportRewriteEvaluationCount, 1)
        XCTAssertFalse(
            resource.dynamicImportRewriteGeneratedBundleArtifactsMutated
        )
        XCTAssertEqual(resource.dynamicImportBlockers, [])
        XCTAssertEqual(
            resource.dynamicImportRecords.first?.resolvedRelativePath,
            "dependency.js"
        )
        XCTAssertEqual(resource.dynamicImportRecords.first?.rewritten, true)
        XCTAssertEqual(resource.dynamicImportRecords.first?.evaluated, true)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnMessage))
        XCTAssertEqual(
            result.responsePayload,
            .object([
                "loaded": .string("dependency-loaded"),
                "value": .string("after-rewrite"),
            ])
        )
        XCTAssertEqual(result.resultKind, .delivered)
        XCTAssertEqual(try Data(contentsOf: backgroundURL), backgroundBefore)
        XCTAssertEqual(try Data(contentsOf: dependencyURL), dependencyBefore)
    }

    func testDynamicImportRewriteBlocksUnsafeAndComputedSpecifiers() throws {
        let cases: [(String, ChromeMV3ServiceWorkerJSDynamicImportBlocker)] = [
            ("import('missing.js');", .importedModuleMissing),
            ("import('../outside.js');", .importPathTraversalRejected),
            ("import('/Users/example/outside.js');", .absoluteFilesystemPathRejected),
            ("import('https://example.com/remote.js');", .remoteURLRejected),
            ("import('data:text/javascript,0');", .dataURLRejected),
            ("import('blob:https://example.com/id');", .blobURLRejected),
            ("import('file:///tmp/worker.js');", .fileURLRejected),
            ("const path = './dependency.js'; import(path);", .dynamicImportArgumentNonString),
            ("import(`./dependency.js`);", .dynamicImportArgumentNonString),
        ]

        for (source, blocker) in cases {
            let fixture = try makeHarness(
                source: source,
                localExperimentalGateAllowed: true,
                dynamicImportRewriteExperimentAllowed: true
            )
            let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
                request: fixture.request()
            )

            XCTAssertEqual(harness.start().status, .blocked, source)
            XCTAssertTrue(
                harness.policy
                    .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate,
                source
            )
            XCTAssertTrue(
                harness.snapshot.resourceLoad?.dynamicImportBlockers.contains(
                    blocker
                ) == true,
                source
            )
            XCTAssertFalse(
                harness.snapshot.resourceLoad?
                    .dynamicImportRewriteExperimentApplied == true,
                source
            )
        }
    }

    func testDynamicImportRewriteBlocksSymlinkUncopiedAndModuleSyntax()
        throws
    {
        let symlinkFixture = try makeHarness(
            source: "import('linked.js');",
            localExperimentalGateAllowed: true,
            dynamicImportRewriteExperimentAllowed: true
        )
        let outside = try temporaryDirectory()
            .appendingPathComponent("outside-module.js")
        try "globalThis.outside = true;"
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

        let uncopiedFixture = try makeHarness(
            source: "import('./dependency.js');",
            localExperimentalGateAllowed: true,
            dynamicImportRewriteExperimentAllowed: true
        )
        try "globalThis.uncopied = true;".write(
            to: uncopiedFixture.generatedRootURL
                .appendingPathComponent("dependency.js"),
            atomically: true,
            encoding: .utf8
        )
        let uncopiedHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: uncopiedFixture.request()
        )

        XCTAssertEqual(uncopiedHarness.start().status, .blocked)
        XCTAssertTrue(
            uncopiedHarness.snapshot.resourceLoad?.dynamicImportBlockers
                .contains(.importedModuleNotCopiedFromGeneratedBundleRecord)
                == true
        )

        let moduleFixture = try makeHarness(
            source: "import('./module.js');",
            localExperimentalGateAllowed: true,
            dynamicImportRewriteExperimentAllowed: true
        )
        let moduleRecord = try generatedRecord(
            moduleFixture,
            adding: ["module.js": "export const value = 'unsupported';"]
        )
        let moduleHarness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: moduleFixture.request(generatedRecord: moduleRecord)
        )

        XCTAssertEqual(moduleHarness.start().status, .failed)
        XCTAssertTrue(
            moduleHarness.snapshot.resourceLoad?.dynamicImportBlockers
                .contains(.importedModuleSyntaxUnsupported) == true
        )
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
              sendResponse({ echo: message.value, urlRedacted: sender.__sumiUrlRedacted });
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

        let asyncSendResponse = try startedHarness(
            source:
                """
                chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
                  setTimeout(() => sendResponse({ delayed: message.value }), 0);
                  return true;
                });
                """
        )
        let asyncResult = asyncSendResponse.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["value": .string("queued")])],
            payloadSummary: "queued sendResponse"
        )
        XCTAssertEqual(asyncResult.resultKind, .delivered)
        XCTAssertEqual(
            asyncResult.responsePayload,
            .object(["delayed": .string("queued")])
        )
        XCTAssertTrue(asyncResult.diagnostics.contains {
            $0.contains("draining queued timeout")
        })

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

    func testRuntimeLastErrorIsCallbackScopedStringAndProtonCoercionSafe()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.lastErrorOutsideBefore = typeof chrome.runtime.lastError;
            globalThis.unsupportedError = null;
            globalThis.storageError = null;
            chrome.permissions.request({ permissions: ['clipboardRead'] }, () => {
              const error = chrome.runtime.lastError;
              const message = error.message;
              globalThis.unsupportedError = {
                errorType: typeof error,
                messageType: typeof message,
                message,
                stringValue: String(message),
                templateValue: `${message}`,
                concatenatedValue: message + '',
                symbolToPrimitiveType: typeof message[Symbol.toPrimitive]
              };
            });
            chrome.storage.managed.set({ blocked: true }, () => {
              globalThis.storageError = chrome.runtime.lastError.message;
            }).catch(() => {});
            chrome.runtime.onMessage.addListener(() => ({
              outsideBefore: globalThis.lastErrorOutsideBefore,
              outsideAfter: typeof chrome.runtime.lastError,
              unsupportedError: globalThis.unsupportedError,
              storageError: globalThis.storageError
            }));
            """
        )

        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "observe callback-scoped runtime.lastError"
        )

        XCTAssertTrue(
            harness.policy.runtimeLastErrorAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.runtimeLastErrorAvailableByDefault)
        XCTAssertTrue(harness.policy.runtimeLastErrorCallbackScoped)
        XCTAssertEqual(
            result.responsePayload,
            .object([
                "outsideAfter": .string("undefined"),
                "outsideBefore": .string("undefined"),
                "storageError": .string("chrome.storage.managed is read-only."),
                "unsupportedError": .object([
                    "concatenatedValue":
                        .string(
                            "Unsupported API call chrome.permissions.request."
                        ),
                    "errorType": .string("object"),
                    "message":
                        .string(
                            "Unsupported API call chrome.permissions.request."
                        ),
                    "messageType": .string("string"),
                    "stringValue":
                        .string(
                            "Unsupported API call chrome.permissions.request."
                        ),
                    "symbolToPrimitiveType": .string("undefined"),
                    "templateValue":
                        .string(
                            "Unsupported API call chrome.permissions.request."
                        ),
                ]),
            ])
        )
        XCTAssertTrue(
            harness.snapshot.blockedUnsupportedCalls.contains(
                "chrome.permissions.request"
            )
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains {
                $0.contains(
                    "chrome.runtime.lastError.message.Symbol(Symbol.toPrimitive)"
                )
            }
        )
    }

    func testRuntimeLastErrorIsVisibleDuringPortDisconnectErrorOnly() throws {
        let harness = try startedHarness(
            source: """
            globalThis.disconnectScope = null;
            chrome.runtime.onConnect.addListener((port) => {
              port.onDisconnect.addListener(() => {
                const error = chrome.runtime.lastError;
                globalThis.disconnectScope = {
                  errorType: typeof error,
                  message: error.message,
                  messageType: typeof error.message
                };
              });
            });
            chrome.runtime.onMessage.addListener(() => ({
              disconnectScope: globalThis.disconnectScope,
              outsideType: typeof chrome.runtime.lastError
            }));
            """
        )
        let connected = harness.connectRuntime(name: "last-error-port")
        let portID = try XCTUnwrap(connected.portID)

        XCTAssertTrue(
            harness.disconnectPort(
                portID: portID,
                reason: "fixturePortError",
                lastErrorMessage: "Fixture Port disconnected."
            )
        )
        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "observe Port disconnect runtime.lastError"
        )

        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "disconnectScope": .object([
                    "errorType": .string("object"),
                    "message": .string("Fixture Port disconnected."),
                    "messageType": .string("string"),
                ]),
                "outsideType": .string("undefined"),
            ])
        )
    }

    func testRuntimeSendMessagePolicyIsLocalExperimentalAndDefaultOff()
        throws
    {
        let defaultGate = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .enabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: false,
            generatedBundleRecordAvailable: true
        )
        let disabledModule = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .disabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: true,
            generatedBundleRecordAvailable: true
        )
        let available = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .enabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: true,
            generatedBundleRecordAvailable: true
        )

        XCTAssertFalse(
            defaultGate.runtimeSendMessageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(defaultGate.runtimeSendMessageAvailableByDefault)
        XCTAssertTrue(
            defaultGate.runtimeSendMessageBlockers.contains(
                "localExperimentalGateRequired"
            )
        )
        XCTAssertFalse(
            disabledModule.runtimeSendMessageAvailableInLocalExperimentalGate
        )
        XCTAssertTrue(
            disabledModule.runtimeSendMessageBlockers.contains(
                "moduleDisabled"
            )
        )
        XCTAssertTrue(available.runtimeSendMessageAvailableInLocalExperimentalGate)
        XCTAssertFalse(available.runtimeSendMessageAvailableByDefault)
        XCTAssertTrue(available.runtimeSendMessageSameExtensionOnly)
        XCTAssertFalse(available.crossExtensionMessagingAllowed)
        XCTAssertFalse(available.hiddenPageCreationAllowed)
        XCTAssertFalse(available.arbitraryWorkerWakeAllowed)
        XCTAssertTrue(available.runtimeSendMessageBlockers.isEmpty)
    }

    func testRuntimeSendMessageRoutesSameExtensionCallbackAndPromise()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.callbackPayload = null;
            globalThis.callbackLastErrorInside = null;
            globalThis.promisePayload = null;

            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
              if (message && message.kind === 'callback') {
                sendResponse({
                  echo: message.value,
                  senderId: sender.id,
                  redacted: sender.__sumiUrlRedacted
                });
                return;
              }
              if (message && message.kind === 'promise') {
                return { echo: message.value };
              }
              if (message && message.kind === 'observe') {
                return {
                  callbackPayload: globalThis.callbackPayload,
                  callbackLastErrorInside: globalThis.callbackLastErrorInside,
                  promisePayload: globalThis.promisePayload,
                  lastErrorOutside: typeof chrome.runtime.lastError
                };
              }
              return undefined;
            });

            chrome.runtime.sendMessage({ kind: 'callback', value: 'cb' }, (response) => {
              globalThis.callbackPayload = response;
              globalThis.callbackLastErrorInside = chrome.runtime.lastError
                ? chrome.runtime.lastError.message
                : null;
            });
            chrome.runtime.sendMessage({ kind: 'promise', value: 'pr' }).then((response) => {
              globalThis.promisePayload = response;
            });
            """
        )

        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["kind": .string("observe")])],
            payloadSummary: "observe runtime.sendMessage"
        )

        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "callbackLastErrorInside": .null,
                "callbackPayload": .object([
                    "echo": .string("cb"),
                    "redacted": .bool(true),
                    "senderId":
                        .string("service-worker-js-fixture-extension"),
                ]),
                "lastErrorOutside": .string("undefined"),
                "promisePayload": .object(["echo": .string("pr")]),
            ])
        )
        XCTAssertEqual(harness.snapshot.runtimeSendMessageRecords.count, 2)
        XCTAssertTrue(
            harness.snapshot.runtimeSendMessageRecords.allSatisfy {
                $0.sameExtensionOnly
                    && !$0.crossExtension
                    && $0.routedListenerCount == 1
                    && $0.resultKind == "delivered"
                    && $0.messageShape == "object:keyCount=2"
            }
        )
        XCTAssertEqual(
            harness.snapshot.runtimeSendMessageRecords
                .compactMap(\.responseShape)
                .sorted(),
            ["object:keyCount=1", "object:keyCount=3"]
        )
        XCTAssertTrue(
            harness.snapshot.precedingChromeAPICalls.contains(
                "chrome.runtime.sendMessage"
            )
        )
        XCTAssertFalse(
            harness.snapshot.blockedUnsupportedCalls.contains(
                "chrome.runtime.sendMessage"
            )
        )
    }

    func testRuntimeSendMessageNoListenerCallbackLastErrorIsDeterministic()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.noReceiverInside = null;
            chrome.runtime.sendMessage({ kind: 'missing' }, () => {
              globalThis.noReceiverInside = chrome.runtime.lastError
                && chrome.runtime.lastError.message;
            });
            globalThis.noReceiverOutside = typeof chrome.runtime.lastError;
            chrome.runtime.onMessage.addListener((message) => {
              if (message && message.kind === 'observe') {
                return {
                  noReceiverInside: globalThis.noReceiverInside,
                  noReceiverOutside: globalThis.noReceiverOutside,
                  outsideNow: typeof chrome.runtime.lastError
                };
              }
              return undefined;
            });
            """
        )

        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["kind": .string("observe")])],
            payloadSummary: "observe runtime.sendMessage no receiver"
        )

        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "noReceiverInside":
                    .string(
                        "Could not establish connection. Receiving end does not exist."
                    ),
                "noReceiverOutside": .string("undefined"),
                "outsideNow": .string("undefined"),
            ])
        )
        XCTAssertEqual(
            harness.snapshot.runtimeSendMessageRecords.first?.resultKind,
            "noListener"
        )
        XCTAssertEqual(
            harness.snapshot.runtimeSendMessageRecords.first?.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )
    }

    func testRuntimeSendMessagePromiseListenerThrowCrossExtensionAndRecursion()
        throws
    {
        let harness = try startedHarness(
            source: """
            globalThis.promiseError = null;
            globalThis.throwError = null;
            globalThis.crossError = null;
            globalThis.recursionError = null;

            chrome.runtime.onMessage.addListener((message) => {
              if (message && message.kind === 'promise-listener') {
                return Promise.resolve('later');
              }
              if (message && message.kind === 'throw') {
                throw new Error('listener failed');
              }
              if (message && message.kind === 'recurse') {
                chrome.runtime.sendMessage({ kind: 'inner' }, () => {
                  globalThis.recursionError = chrome.runtime.lastError
                    && chrome.runtime.lastError.message;
                });
                return { outer: true };
              }
              if (message && message.kind === 'observe') {
                return {
                  promiseError: globalThis.promiseError,
                  throwError: globalThis.throwError,
                  crossError: globalThis.crossError,
                  recursionError: globalThis.recursionError
                };
              }
              return undefined;
            });

            chrome.runtime.sendMessage({ kind: 'promise-listener' }).catch((error) => {
              globalThis.promiseError = error.message;
            });
            chrome.runtime.sendMessage({ kind: 'throw' }).catch((error) => {
              globalThis.throwError = error.message;
            });
            chrome.runtime.sendMessage(
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              { kind: 'external' }
            ).catch((error) => {
              globalThis.crossError = error.message;
            });
            chrome.runtime.sendMessage({ kind: 'recurse' });
            """
        )

        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["kind": .string("observe")])],
            payloadSummary: "observe runtime.sendMessage failures"
        )

        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "crossError":
                    .string(
                        "runtime.sendMessage external-extension overload is blocked in the local experimental service-worker harness."
                    ),
                "promiseError":
                    .string(
                        "Promise completion is observable but deferred by the deterministic no-wait harness policy."
                    ),
                "recursionError":
                    .string(
                        "runtime.sendMessage immediate self-recursion is blocked in the local experimental service-worker harness."
                    ),
                "throwError": .string("listener failed"),
            ])
        )
        let records = harness.snapshot.runtimeSendMessageRecords
        XCTAssertTrue(records.contains { $0.resultKind == "unsupportedListenerMode" })
        XCTAssertTrue(records.contains { $0.resultKind == "listenerError" })
        XCTAssertTrue(records.contains {
            $0.resultKind == "crossExtensionUnsupported" && $0.crossExtension
        })
        XCTAssertTrue(records.contains {
            $0.resultKind == "recursionBlocked" && $0.recursionBlocked
        })
    }

    func testRuntimeConnectPortMessageDeliveryDisconnectAndKeepaliveRelease()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              port.onMessage.addListener((message) => {
                port.postMessage({
                  echo: message.value,
                  name: port.name,
                  senderId: port.sender.id,
                  tabId: port.sender.tab && port.sender.tab.id,
                  frameId: port.sender.frameId,
                  documentId: port.sender.documentId,
                  hasURL: Object.prototype.hasOwnProperty.call(port.sender, 'url'),
                  redaction: port.sender.__sumiRedactionState
                });
              });
              port.onDisconnect.addListener(() => {});
            });
            """
        )

        let connected = harness.connectRuntime(
            name: "fixture-channel",
            sender: ChromeMV3ServiceWorkerEventSenderMetadata(
                tabID: 7,
                frameID: 2,
                documentID: "document-7",
                sourceURL: "https://example.com/private",
                urlRedacted: true,
                redactionState: "unit test redacted sender URL"
            ),
            source: .contentScriptRuntimeConnect
        )
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
                    "documentId": .string("document-7"),
                    "echo": .string("port-value"),
                    "frameId": .number(2),
                    "hasURL": .bool(false),
                    "name": .string("fixture-channel"),
                    "redaction": .string("unit test redacted sender URL"),
                    "senderId": .string("service-worker-js-fixture-extension"),
                    "tabId": .number(7),
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

    func testCapturedListenersDispatchAfterTopLevelFailureBeforeTeardown()
        throws
    {
        let fixture = try makeHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              port.onMessage.addListener((message) => {
                port.postMessage({ echo: message.value, name: port.name });
              });
              port.onDisconnect.addListener(() => {});
            });
            chrome.alarms.onAlarm.addListener((alarm) => {
              globalThis.observedAlarm = {
                name: alarm.name,
                scheduledTime: alarm.scheduledTime,
                eventSource: alarm.__sumiEventSource
              };
            });
            chrome.runtime.onMessage.addListener(() => ({
              observedAlarm: globalThis.observedAlarm || null
            }));
            throw new TypeError('late top-level failure');
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        let started = harness.start()
        XCTAssertEqual(started.status, .failed)
        XCTAssertTrue(started.blockers.contains(.scriptEvaluationFailed))
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnConnect))
        XCTAssertTrue(harness.capturedListener(for: .alarmsOnAlarm))
        XCTAssertTrue(harness.canDispatchCapturedListeners)

        let connected = harness.connectRuntime(name: "fixture-channel")
        let portID = try XCTUnwrap(connected.portID)
        let delivered = harness.deliverPortMessage(
            portID: portID,
            message: .object(["value": .string("port-value")])
        )
        XCTAssertEqual(connected.resultKind, .delivered)
        XCTAssertEqual(
            delivered?.postedMessages,
            [
                .object([
                    "echo": .string("port-value"),
                    "name": .string("fixture-channel"),
                ]),
            ]
        )
        XCTAssertTrue(harness.disconnectPort(portID: portID))

        let alarm = harness.dispatch(
            source: .alarmTriggered,
            arguments: [
                .object([
                    "name": .string("fixture-alarm"),
                    "scheduledTime": .number(42),
                ]),
            ],
            payloadSummary: "captured failure alarm"
        )
        XCTAssertEqual(alarm.resultKind, .delivered)

        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "observe captured failure alarm"
        )
        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "observedAlarm": .object([
                    "eventSource": .string("localExperimentalSyntheticAlarm"),
                    "name": .string("fixture-alarm"),
                    "scheduledTime": .number(42),
                ]),
            ])
        )

        _ = harness.triggerIdleRelease()
        XCTAssertFalse(harness.canDispatchCapturedListeners)
    }

    func testStoragePermissionsAlarmContextMenuAndWebNavigationDispatch()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.storage.onChanged.addListener(() => {});
            chrome.permissions.onAdded.addListener(async (permissions) => {
              await Promise.resolve();
              globalThis.addedPermissions = permissions.permissions.join(',');
            });
            chrome.permissions.onRemoved.addListener(async (permissions) => {
              await Promise.resolve();
              globalThis.removedPermissions = permissions.permissions.join(',');
            });
            chrome.alarms.onAlarm.addListener((alarm) => {
              globalThis.alarmPayload = {
                name: alarm.name,
                scheduledTime: alarm.scheduledTime,
                hasPeriod: Object.prototype.hasOwnProperty.call(alarm, 'periodInMinutes'),
                eventSource: alarm.__sumiEventSource
              };
            });
            chrome.contextMenus.onClicked.addListener(() => {});
            chrome.webNavigation.onCommitted.addListener(() => {});
            chrome.runtime.onMessage.addListener(() => ({
              addedPermissions: globalThis.addedPermissions || null,
              removedPermissions: globalThis.removedPermissions || null,
              alarmPayload: globalThis.alarmPayload || null
            }));
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
            let arguments: [ChromeMV3StorageValue]
            switch source {
            case .permissionsAdded, .permissionsRemoved:
                arguments = [
                    .object([
                        "permissions": .array([.string("storage")]),
                        "origins": .array([]),
                    ]),
                ]
            case .alarmTriggered:
                arguments = [
                    .object([
                        "name": .string("fixture-alarm"),
                        "scheduledTime": .number(123),
                    ]),
                ]
            default:
                arguments = [.object(["fixture": .bool(true)])]
            }
            let result = harness.dispatch(
                source: source,
                arguments: arguments,
                payloadSummary: source.rawValue
            )
            XCTAssertEqual(result.resultKind, .delivered, source.rawValue)
            XCTAssertEqual(
                result.lifecycleRoutingRecord?.resultKind,
                .delivered,
                source.rawValue
            )
        }
        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "observe event payloads"
        )
        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "addedPermissions": .string("storage"),
                "alarmPayload": .object([
                    "eventSource": .string("localExperimentalSyntheticAlarm"),
                    "hasPeriod": .bool(false),
                    "name": .string("fixture-alarm"),
                    "scheduledTime": .number(123),
                ]),
                "removedPermissions": .string("storage"),
            ])
        )
    }

    func testChromeStorageAreasUseScopedInMemoryStorage() throws {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onMessage.addListener((message) => {
              if (message && message.kind === 'write') {
                chrome.storage.local.set({ localKey: 'local-value' }, () => {
                  chrome.storage.local.get('localKey', (items) => {
                    globalThis.localValue = items.localKey;
                  });
                });
                chrome.storage.session.get({ missing: 'default-value' }, (items) => {
                  globalThis.sessionDefault = items.missing;
                });
                return { accepted: true };
              }
              return {
                keys: typeof chrome.storage.local.getKeys === 'function',
                localValue: globalThis.localValue || null,
                sessionDefault: globalThis.sessionDefault || null
              };
            });
            """
        )

        let write = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [
                .object(["kind": .string("write")]),
            ],
            payloadSummary: "write scoped storage"
        )
        XCTAssertEqual(
            write.responsePayload,
            .object(["accepted": .bool(true)])
        )

        let observed = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "observe scoped storage"
        )
        XCTAssertEqual(
            observed.responsePayload,
            .object([
                "keys": .bool(true),
                "localValue": .string("local-value"),
                "sessionDefault": .string("default-value"),
            ])
        )
    }

    func testChromeStorageMissingKeysCallbacksPromisesAndReportsAreRedacted()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onMessage.addListener((message) => {
              if (message && message.kind === 'write') {
                chrome.storage.local.get('missing-key', (items) => {
                  globalThis.callbackMissingKeys = Object.keys(items).length;
                });
                chrome.storage.local.get('missing-key').then((items) => {
                  globalThis.promiseMissingKeys = Object.keys(items).length;
                });
                chrome.storage.session.get({ missingDefault: 'fallback' }).then((items) => {
                  globalThis.promiseDefault = items.missingDefault;
                });
                chrome.storage.local.set({
                  'vault-token-super-secret': 'secret-value'
                });
                return { accepted: true };
              }
              return {
                callbackMissingKeys: globalThis.callbackMissingKeys,
                promiseMissingKeys: globalThis.promiseMissingKeys,
                promiseDefault: globalThis.promiseDefault
              };
            });
            """
        )

        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                arguments: [.object(["kind": .string("write")])],
                payloadSummary: "write redacted scoped storage"
            ).responsePayload,
            .object(["accepted": .bool(true)])
        )
        XCTAssertEqual(
            harness.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "observe redacted scoped storage"
            ).responsePayload,
            .object([
                "callbackMissingKeys": .number(0),
                "promiseDefault": .string("fallback"),
                "promiseMissingKeys": .number(0),
            ])
        )

        let snapshot = harness.snapshot
        XCTAssertTrue(snapshot.storageOperationRecords.contains {
            $0.area == "local"
                && $0.operation == "get"
                && $0.keySelectorKind == "string"
                && $0.callbackProvided
                && $0.promiseReturned
                && !$0.valuesRecorded
                && $0.resultShape == "object:keyCount=0"
                && $0.emptyResult
                && !$0.populatedResult
        })
        XCTAssertTrue(snapshot.storageOperationRecords.contains {
            $0.area == "session"
                && $0.operation == "get"
                && $0.keySelectorKind == "defaultsObject"
                && !$0.valuesRecorded
                && $0.resultShape == "object:keyCount=1"
                && $0.populatedResult
        })
        XCTAssertTrue(snapshot.storageOperationRecords.allSatisfy {
            $0.keyFingerprints.allSatisfy {
                $0.hasPrefix("redacted-key:length=")
                    && $0.contains(":saltedHash=")
            }
        })
        let encoded = try JSONEncoder().encode(snapshot)
        let report = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(report.contains("vault-token-super-secret"))
        XCTAssertFalse(report.contains("secret-value"))
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
            generatedBundleRecordAvailable: true,
            dynamicImportRewriteExperimentAllowed: true
        )

        XCTAssertFalse(policy.serviceWorkerJSExecutionAvailableByDefault)
        XCTAssertFalse(policy.dynamicImportRewriteExperimentAvailableByDefault)
        XCTAssertFalse(policy.dynamicImportRewriteExperimentMutatesGeneratedBundle)
        XCTAssertFalse(policy.permanentBackgroundAvailable)
        XCTAssertTrue(policy.timersAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.timersAvailableByDefault)
        XCTAssertFalse(policy.wallClockTimersAllowed)
        XCTAssertTrue(policy.timersAllowed)
        XCTAssertFalse(policy.pollingAllowed)
        XCTAssertTrue(policy.webCryptoAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.webCryptoAvailableByDefault)
        XCTAssertTrue(policy.i18nGetUILanguageAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.i18nGetUILanguageAvailableByDefault)
        XCTAssertTrue(policy.i18nGetMessageAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.i18nGetMessageAvailableByDefault)
        XCTAssertTrue(policy.i18nGeneratedBundleLocalesOnly)
        XCTAssertFalse(policy.i18nNetworkLocalesAllowed)
        XCTAssertFalse(policy.i18nFilesystemLocaleFallbackAllowed)
        XCTAssertFalse(policy.i18nSelectedUILanguage.isEmpty)
        XCTAssertFalse(policy.i18nUnsupportedAPIs.contains("chrome.i18n.getMessage"))
        XCTAssertTrue(policy.alarmsAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.alarmsAvailableByDefault)
        XCTAssertFalse(policy.wallClockAlarmSchedulingAllowed)
        XCTAssertFalse(policy.backgroundWakeAllowed)
        XCTAssertTrue(policy.explicitAlarmTriggerOnly)
        XCTAssertTrue(
            policy.workerGlobalEventTargetAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(policy.workerGlobalEventTargetAvailableByDefault)
        XCTAssertTrue(
            policy.workerGlobalEventTargetSupportedTypes.contains("message")
        )
        XCTAssertFalse(policy.workerGlobalWindowDocumentExposed)
        XCTAssertTrue(policy.fetchClassificationAvailableInLocalExperimentalGate)
        XCTAssertTrue(policy.fetchAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.fetchAvailableByDefault)
        XCTAssertFalse(policy.networkFetchAllowed)
        XCTAssertTrue(policy.extensionLocalFetchAllowed)
        XCTAssertTrue(policy.generatedBundleOnly)
        XCTAssertFalse(policy.credentialsAllowed)
        XCTAssertFalse(policy.cacheAllowed)
        XCTAssertFalse(policy.fetchNetworkExecutionAllowed)
        XCTAssertTrue(policy.fetchExtensionLocalExecutionAllowed)
        XCTAssertTrue(policy.fetchBlockers.isEmpty)
        XCTAssertTrue(policy.cryptoGetRandomValuesAvailable)
        XCTAssertTrue(policy.cryptoRandomUUIDAvailable)
        XCTAssertTrue(policy.subtleCryptoAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.subtleCryptoAvailableByDefault)
        XCTAssertEqual(policy.subtleCryptoSupportedMethods, ["digest"])
        XCTAssertTrue(policy.subtleCryptoBlockedMethods.contains("deriveBits"))
        XCTAssertTrue(
            policy.subtleCryptoSupportedAlgorithms.contains("digest:SHA-256")
        )
        XCTAssertTrue(policy.subtleCryptoBlockedAlgorithms.contains("PBKDF2"))
    }

    private func startedHarness(
        source: String,
        extraFiles: [String: String] = [:],
        manifestAdditions: [String: Any] = [:],
        uiLanguageOverride: String? = nil
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixture = try makeHarness(
            source: source,
            extraFiles: extraFiles,
            manifestAdditions: manifestAdditions,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(uiLanguageOverride: uiLanguageOverride)
        )
        XCTAssertEqual(harness.start().status, .running)
        return harness
    }

    private struct HarnessFixture {
        var manifest: ChromeMV3Manifest
        var generatedRecord: ChromeMV3GeneratedBundleRecord
        var generatedRootURL: URL
        var localExperimentalGateAllowed: Bool
        var dynamicImportRewriteExperimentAllowed: Bool

        func request(
            manifest: ChromeMV3Manifest? = nil,
            generatedRecord: ChromeMV3GeneratedBundleRecord? = nil,
            moduleState: ChromeMV3ProfileHostModuleState = .enabled,
            extensionEnabled: Bool = true,
            dynamicImportRewriteExperimentAllowed: Bool? = nil,
            uiLanguageOverride: String? = nil
        ) -> ChromeMV3ServiceWorkerJSExecutionRequest {
            ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: manifest ?? self.manifest,
                generatedBundleRecord: generatedRecord ?? self.generatedRecord,
                extensionID: "service-worker-js-fixture-extension",
                profileID: "service-worker-js-fixture-profile",
                moduleState: moduleState,
                extensionEnabled: extensionEnabled,
                localExperimentalGateAllowed:
                    localExperimentalGateAllowed,
                dynamicImportRewriteExperimentAllowed:
                    dynamicImportRewriteExperimentAllowed
                    ?? self.dynamicImportRewriteExperimentAllowed,
                uiLanguageOverride: uiLanguageOverride
            )
        }
    }

    private func makeHarness(
        source: String,
        extraFiles: [String: String] = [:],
        manifestAdditions: [String: Any] = [:],
        serviceWorkerType: String? = nil,
        localExperimentalGateAllowed: Bool = false,
        dynamicImportRewriteExperimentAllowed: Bool = false
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
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Service Worker JS Execution Fixture",
            "version": "1.0.0",
            "background": background,
        ]
        for (key, value) in manifestAdditions {
            manifest[key] = value
        }
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
            localExperimentalGateAllowed: localExperimentalGateAllowed,
            dynamicImportRewriteExperimentAllowed:
                dynamicImportRewriteExperimentAllowed
        )
    }

    private func generatedRecord(
        _ fixture: HarnessFixture,
        adding files: [String: String] = [:],
        addingBinary binaryFiles: [String: Data] = [:]
    ) throws -> ChromeMV3GeneratedBundleRecord {
        var record = fixture.generatedRecord
        for (path, source) in files {
            let url = fixture.generatedRootURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try source.write(to: url, atomically: true, encoding: .utf8)
            if record.copiedResourcePaths.contains(path) == false {
                record.copiedResourcePaths.append(path)
            }
        }
        for (path, data) in binaryFiles {
            let url = fixture.generatedRootURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
            if record.copiedResourcePaths.contains(path) == false {
                record.copiedResourcePaths.append(path)
            }
        }
        record.copiedResourcePaths.sort()
        return record
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

    private func safeDebugToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.count <= 220,
              trimmed.lowercased().contains("token") == false,
              trimmed.lowercased().contains("password") == false,
              trimmed.range(
                of: #"^[A-Za-z0-9._+/\-:=,() ]+$"#,
                options: .regularExpression
              ) != nil
        else { return "redacted" }
        return trimmed
    }

}
