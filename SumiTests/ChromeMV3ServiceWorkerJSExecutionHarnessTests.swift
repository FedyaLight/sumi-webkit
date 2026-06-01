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
            moduleDisabled.policy.timersAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.timersAvailableByDefault)
        XCTAssertFalse(moduleDisabled.policy.wallClockTimersAllowed)
        XCTAssertFalse(
            moduleDisabled.policy.webCryptoAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.webCryptoAvailableByDefault)
        XCTAssertFalse(
            moduleDisabled.policy.i18nGetUILanguageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(moduleDisabled.policy.i18nGetUILanguageAvailableByDefault)
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
        XCTAssertFalse(harness.policy.webCryptoAvailableInLocalExperimentalGate)
        XCTAssertFalse(harness.policy.webCryptoAvailableByDefault)
        XCTAssertFalse(
            harness.policy.i18nGetUILanguageAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(harness.policy.i18nGetUILanguageAvailableByDefault)
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
              getMessageResult: getMessageResult === undefined ? null : getMessageResult,
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
                "getMessageResult": .null,
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
            harness.policy.i18nUnsupportedAPIs.contains(
                "chrome.i18n.getMessage"
            )
        )
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
                    && $0.status == "blocked"
                    && $0.blocker == "unsupportedI18nAPI"
            }
        )
        XCTAssertTrue(
            harness.snapshot.blockedUnsupportedCalls.contains(
                "chrome.i18n.getMessage"
            )
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
        XCTAssertFalse(policy.i18nSelectedUILanguage.isEmpty)
        XCTAssertTrue(
            policy.i18nUnsupportedAPIs.contains("chrome.i18n.getMessage")
        )
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
        uiLanguageOverride: String? = nil
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixture = try makeHarness(
            source: source,
            extraFiles: extraFiles,
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
            localExperimentalGateAllowed: localExperimentalGateAllowed,
            dynamicImportRewriteExperimentAllowed:
                dynamicImportRewriteExperimentAllowed
        )
    }

    private func generatedRecord(
        _ fixture: HarnessFixture,
        adding files: [String: String]
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

}
