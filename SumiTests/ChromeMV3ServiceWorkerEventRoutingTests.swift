import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerEventRoutingTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testReadinessAcceptsSafeDeclaredWorkerWithGeneratedResources()
        throws
    {
        let root = try makeBundle(
            serviceWorkerSource:
                "chrome.runtime.onMessage.addListener(() => true);\n"
                + "chrome.storage.onChanged.addListener(() => {});\n"
        )
        let readiness = ChromeMV3ServiceWorkerDeclarationReadinessEvaluator
            .evaluate(
                manifest: try manifest(),
                generatedBundleRootURL: root,
                extensionID: "ready-extension",
                profileID: "ready-profile",
                localExperimentalGateAllowed: true
            )

        XCTAssertEqual(readiness.backgroundServiceWorkerPath, "background.js")
        XCTAssertEqual(readiness.serviceWorkerType, "classic")
        XCTAssertTrue(readiness.serviceWorkerFileAvailable)
        XCTAssertTrue(readiness.serviceWorkerWrapperAvailable)
        XCTAssertTrue(readiness.wrapperShimAvailable)
        XCTAssertTrue(readiness.eventRoutingAvailable)
        XCTAssertTrue(readiness.runtimeLoadable == false)
        XCTAssertTrue(readiness.listenerDetected(for: .runtimeOnMessage))
        XCTAssertTrue(readiness.listenerDetected(for: .storageOnChanged))
    }

    func testReadinessBlocksDefaultGateMissingFileAndUnsafePath() throws {
        let root = try makeBundle(serviceWorkerSource: nil)
        let missing = ChromeMV3ServiceWorkerDeclarationReadinessEvaluator
            .evaluate(
                manifest: try manifest(),
                generatedBundleRootURL: root,
                extensionID: "missing-extension",
                profileID: "missing-profile",
                localExperimentalGateAllowed: true
            )
        let defaultOff = ChromeMV3ServiceWorkerDeclarationReadinessEvaluator
            .evaluate(
                manifest: try manifest(),
                generatedBundleRootURL: root,
                extensionID: "gate-extension",
                profileID: "gate-profile"
            )
        let unsafe = ChromeMV3ServiceWorkerDeclarationReadinessEvaluator
            .evaluate(
                manifest: unsafeManifest(serviceWorkerPath: "../background.js"),
                generatedBundleRootURL: root,
                extensionID: "unsafe-extension",
                profileID: "unsafe-profile",
                localExperimentalGateAllowed: true
            )

        XCTAssertFalse(missing.eventRoutingAvailable)
        XCTAssertTrue(missing.blockers.contains(.serviceWorkerFileMissing))
        XCTAssertFalse(defaultOff.eventRoutingAvailable)
        XCTAssertEqual(defaultOff.localExperimentalGateState, .runtimeGateBlocked)
        XCTAssertTrue(defaultOff.blockers.contains(.localExperimentalGateBlocked))
        XCTAssertFalse(unsafe.eventRoutingAvailable)
        XCTAssertTrue(unsafe.blockers.contains(.serviceWorkerPathUnsafe))
    }

    func testRouterDeliversNoReceiverAndBlockedByGateDeterministically()
        throws
    {
        let session = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(
                    profileID: "route-profile",
                    extensionID: "route-extension"
                )
        )
        let component = session.attachComponent(
            kind: .extensionPageHostHarness,
            componentID: "route-popup",
            eventSurfaces: [.runtimeOnMessage]
        )
        session.registerListener(
            event: .runtimeOnMessage,
            listenerID: "route-runtime-on-message",
            outcome: .modelDispatched(.string("route-ok"))
        )
        let ready = ChromeMV3ServiceWorkerDeclarationReadiness(
            schemaVersion: 1,
            extensionID: "route-extension",
            profileID: "route-profile",
            backgroundServiceWorkerPath: "background.js",
            serviceWorkerType: "classic",
            generatedBundleRootPath: "/tmp/route",
            generatedServiceWorkerResourcePath: "/tmp/route/background.js",
            serviceWorkerFileAvailable: true,
            serviceWorkerPathSafe: true,
            serviceWorkerWrapperPath: "/tmp/route/_sumi_runtime/wrapper.js",
            serviceWorkerWrapperAvailable: true,
            wrapperShimPath: "/tmp/route/_sumi_runtime/shim.js",
            wrapperShimAvailable: true,
            listenerDiscoveryStrategy: "test",
            listenerCoverage: [
                ChromeMV3ServiceWorkerListenerCoverage(
                    event: .runtimeOnMessage,
                    listenerSurface: .runtimeOnMessageServiceWorker,
                    listenerDetected: true,
                    detectionPattern:
                        "chrome.runtime.onMessage.addListener",
                    diagnostics: []
                ),
                ChromeMV3ServiceWorkerListenerCoverage(
                    event: .runtimeOnConnect,
                    listenerSurface: .runtimeOnConnectServiceWorker,
                    listenerDetected: false,
                    detectionPattern: nil,
                    diagnostics: []
                ),
            ],
            eventRoutingAvailable: true,
            localExperimentalGateState: .allowed,
            runtimeLoadable: false,
            blockers: [],
            diagnostics: ["test readiness"]
        )
        var blocked = ready
        blocked.eventRoutingAvailable = false
        blocked.blockers = [.localExperimentalGateBlocked]

        let delivered = ChromeMV3ServiceWorkerEventRouter.route(
            source: .popupOptionsRuntimeMessage,
            readiness: ready,
            sharedLifecycleSession: session,
            payload: .object(["ping": .bool(true)]),
            payloadSummary: "popup sendMessage",
            sourceComponentID: component.componentID,
            sourceComponentKind: .extensionPageHostHarness
        )
        let noReceiver = ChromeMV3ServiceWorkerEventRouter.route(
            source: .popupOptionsRuntimeConnect,
            readiness: ready,
            sharedLifecycleSession: session,
            payloadSummary: "popup connect",
            sourceComponentID: component.componentID,
            sourceComponentKind: .extensionPageHostHarness
        )
        let gate = ChromeMV3ServiceWorkerEventRouter.route(
            source: .popupOptionsRuntimeMessage,
            readiness: blocked,
            sharedLifecycleSession: session,
            payloadSummary: "blocked sendMessage",
            sourceComponentID: component.componentID,
            sourceComponentKind: .extensionPageHostHarness
        )

        XCTAssertEqual(delivered.resultKind, .delivered)
        XCTAssertEqual(delivered.responsePayload, .string("route-ok"))
        XCTAssertEqual(noReceiver.resultKind, .noReceiver)
        XCTAssertEqual(
            noReceiver.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertEqual(gate.resultKind, .blockedByGate)
    }

    private func makeBundle(serviceWorkerSource: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        if let serviceWorkerSource {
            try serviceWorkerSource.write(
                to: directory.appendingPathComponent("background.js"),
                atomically: true,
                encoding: .utf8
            )
        }
        for module in [
            ChromeMV3RuntimeTemplateModuleName.serviceWorkerWrapperClassic,
            .chromeShimServiceWorker,
        ] {
            let template = ChromeMV3RuntimeResourceTemplateCatalog
                .template(named: module)
            let url = directory.appendingPathComponent(
                template.outputRelativePath
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try template.contents.write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        }
        return directory
    }

    private func manifest(
        serviceWorkerPath: String = "background.js"
    ) throws -> ChromeMV3Manifest {
        try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Service Worker Routing",
            "version": "1.0.0",
            "background": [
                "service_worker": serviceWorkerPath,
            ],
        ])
    }

    private func unsafeManifest(
        serviceWorkerPath: String
    ) -> ChromeMV3Manifest {
        ChromeMV3Manifest(
            manifestVersion: 3,
            name: "Unsafe Service Worker Routing",
            version: "1.0.0",
            description: nil,
            background: ChromeMV3Background(
                serviceWorker: serviceWorkerPath,
                type: nil
            ),
            permissions: [],
            optionalPermissions: [],
            hostPermissions: [],
            optionalHostPermissions: [],
            contentScripts: [],
            action: nil,
            optionsPage: nil,
            optionsUI: nil,
            webAccessibleResources: [],
            externallyConnectable: nil,
            declarativeNetRequest: nil,
            sidePanel: nil,
            oauth2: nil,
            commands: [:],
            minimumChromeVersion: nil,
            browserSpecificSettings: [:],
            devtoolsPage: nil,
            topLevelKeys: [
                "manifest_version",
                "name",
                "version",
                "background",
            ]
        )
    }
}
