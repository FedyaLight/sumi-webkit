import WebKit
import XCTest

@testable import Sumi

/// Integration tests for typed callback-evidence admission on the WebKit
/// `connectUsing` native-messaging delegate callback. `WKWebExtension`
/// message ports cannot be constructed in tests, so connect is driven
/// through the exact settlement seam the delegate bridge uses, starting
/// from freshly captured (and asserted admissible) evidence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingConnectCallbackAdmissionTests:
    ExtensionNativeMessagingAdmissionTestCase {
    // MARK: - 11. Exact current connect registers exactly one session

    func testExactCurrentConnectRegistersSingleSession() async throws {
        let harness = try await makeHarness(name: "ConnectExact")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        adapter.completesImmediately = true
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.fixtureHostBundleID

        let result = try await driveConnect(harness: harness, port: port)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(adapter.connectRequestCount, 1)
        XCTAssertEqual(harness.inspection.nativeMessaging.ports.count, 1)
        XCTAssertNotNil(
            harness.inspection.nativeMessaging.ports.registeredHandler(for: port)
        )
        XCTAssertFalse(port.isDisconnected)
    }

    // MARK: - 12. A superseded controller binding cannot register a session

    func testWrongControllerBindingConnectFailsClosedWithoutSession() async throws {
        let harness = try await makeHarness(name: "ConnectWrongController")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.fixtureHostBundleID
        let foreignController = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        let result = try await driveConnect(
            harness: harness,
            port: port,
            beforeSettlement: { _ in
                harness.inspection.contextState.profiles.setController(
                    foreignController,
                    for: harness.profileID
                )
            }
        )

        assertIsStaleCallbackError(result.error)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(adapter.connectRequestCount, 0)
        XCTAssertEqual(harness.inspection.nativeMessaging.ports.count, 0)
        XCTAssertTrue(port.isDisconnected)
    }

    // MARK: - 13. Context replacement before registration leaves no handler

    func testContextReplacementBeforeRegistrationLeavesNoHandler() async throws {
        let harness = try await makeHarness(name: "ConnectContextReplacement")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.fixtureHostBundleID
        let replacement = WKWebExtensionContext(
            for: harness.context.webExtension
        )

        let result = try await driveConnect(
            harness: harness,
            port: port,
            beforeSettlement: { _ in
                _ = harness.inspection.contextState.profiles.setContext(
                    replacement,
                    extensionId: harness.extensionID,
                    profileId: harness.profileID
                )
            }
        )

        assertIsStaleCallbackError(result.error)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(adapter.connectRequestCount, 0)
        XCTAssertEqual(harness.inspection.nativeMessaging.ports.count, 0)
        XCTAssertNil(
            harness.inspection.nativeMessaging.ports.registeredHandler(for: port)
        )
        XCTAssertTrue(port.isDisconnected)
    }

    // MARK: - 14. Reentrant invalidation during registration clears the session

    func testReentrantInvalidationDuringRegistrationClearsStaleSession() async throws {
        let harness = try await makeHarness(name: "ConnectReentrantRegistration")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.fixtureHostBundleID
        // The session wires the physical port during construction, before
        // the registration claim; a reentrant rebind there must stop the
        // connect tail and leave no session behind.
        var didFire = false
        port.onMessageHandlerWired = {
            guard didFire == false else { return }
            didFire = true
            _ = harness.inspection.contextState.profiles.setContext(
                harness.context,
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        }

        let result = try await driveConnect(harness: harness, port: port)

        XCTAssertTrue(didFire)
        assertIsStaleCallbackError(result.error)
        XCTAssertEqual(result.completionCalls, 1)
        XCTAssertEqual(adapter.connectRequestCount, 0)
        XCTAssertEqual(harness.inspection.nativeMessaging.ports.count, 0)
        XCTAssertTrue(port.isDisconnected)
    }

    // MARK: - 15. A physical port cannot be rebound to a second live session

    func testDuplicatePhysicalPortConnectIsRejectedWithoutReplacingSession() async throws {
        let harness = try await makeHarness(name: "ConnectDuplicatePort")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        adapter.completesImmediately = true
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.fixtureHostBundleID

        let firstResult = try await driveConnect(harness: harness, port: port)
        XCTAssertNil(firstResult.error)
        let firstSession = try XCTUnwrap(
            harness.inspection.nativeMessaging.ports.registeredHandler(for: port)
        )

        // A duplicate callback for the same physical port must fail before a
        // second session can overwrite the port's handlers.
        let secondResult = try await driveConnect(harness: harness, port: port)
        XCTAssertNotNil(secondResult.error)
        XCTAssertEqual(secondResult.completionCalls, 1)
        XCTAssertEqual(adapter.connectRequestCount, 1)

        XCTAssertIdentical(
            harness.inspection.nativeMessaging.ports.registeredHandler(for: port),
            firstSession
        )
        XCTAssertEqual(harness.inspection.nativeMessaging.ports.count, 1)
        XCTAssertFalse(port.isDisconnected)
    }

    // MARK: - 16. A reused port key cannot be mutated by a stale claim

    func testPortKeyReuseCannotBeMutatedByStaleClaim() async throws {
        let harness = try await makeHarness(name: "ConnectPortKeyReuse")
        let registry = harness.inspection.nativeMessaging.ports
        let port = MockNativeMessagingPort()
        let firstSession = makeBarePortSession(port: port)
        let secondSession = makeBarePortSession(port: port)

        let firstClaim = try XCTUnwrap(registry.register(
            handler: firstSession,
            port: port,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        ))
        let duplicateClaim = registry.register(
            handler: secondSession,
            port: port,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )
        XCTAssertNil(duplicateClaim)

        // Neither a made-up future token nor the wrong handler paired with the
        // current token may mutate the live registration.
        registry.unregister(handler: firstSession, port: port, claimToken: firstClaim + 1)
        registry.unregister(handler: secondSession, port: port, claimToken: firstClaim)
        XCTAssertIdentical(registry.registeredHandler(for: port), firstSession)
        XCTAssertEqual(registry.count, 1)

        registry.unregister(handler: firstSession, port: port, claimToken: firstClaim)
        XCTAssertNil(registry.registeredHandler(for: port))
        XCTAssertEqual(registry.count, 0)
    }

    private func makeBarePortSession(
        port: any SumiNativeMessagingPortControlling
    ) -> SumiNativeMessagingPortSession {
        SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: "ext-bare",
            hostBundleIdentifier: Self.fixtureHostBundleID,
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in /* no-op */ },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
    }
}
