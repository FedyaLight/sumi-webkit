import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ProtonPassSafariApplicationIDAdapterTests: XCTestCase {
    func testSupportsObservedProtonSafariExtensionIdentity() throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let installed = try makeInstalledExtension(
            id: "ext-proton",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: ProtonNativeMessagingIdentifiers.safariHostBundleIdentifier,
                appexBundleID: ProtonNativeMessagingIdentifiers.safariExtensionBundleIdentifier
            ),
            name: "Not used for selection"
        )
        let context = makeContext(installed: installed)

        XCTAssertTrue(adapter.supports(context: context))
    }

    func testEnvironmentIsStoredInProfileScopedState() async throws {
        let store = InMemoryProtonPassSafariCompanionStore()
        let adapter = ProtonPassSafariApplicationIDAdapter(store: store)
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"environment":"prod"}"#
        )

        XCTAssertNil(reply.value)
        XCTAssertNil(reply.error)
        let state = try XCTUnwrap(
            store.loadState(
                profileId: context.profileId,
                extensionId: context.extensionId
            )
        )
        XCTAssertEqual(state.environment, "prod")
    }

    func testCredentialsAreStoredThroughSecureStoreAbstraction() async throws {
        let store = InMemoryProtonPassSafariCompanionStore()
        let adapter = ProtonPassSafariApplicationIDAdapter(store: store)
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: """
            {"credentials":{"UID":"uid-1","AccessToken":"access-1","RefreshToken":"refresh-1","UserID":"user-1"}}
            """
        )

        XCTAssertNil(reply.value)
        XCTAssertNil(reply.error)
        let state = try XCTUnwrap(
            store.loadState(
                profileId: context.profileId,
                extensionId: context.extensionId
            )
        )
        XCTAssertEqual(
            state.credentials,
            ProtonPassSafariCredentials(
                uid: "uid-1",
                accessToken: "access-1",
                refreshToken: "refresh-1",
                userId: "user-1"
            )
        )
    }

    func testCredentialsNullClearsOnlyCurrentProfile() async throws {
        let store = InMemoryProtonPassSafariCompanionStore()
        let adapter = ProtonPassSafariApplicationIDAdapter(store: store)
        let firstProfile = UUID()
        let secondProfile = UUID()
        let firstContext = try makeProtonContext(profileId: firstProfile)
        let secondContext = try makeProtonContext(profileId: secondProfile)
        try store.saveState(
            ProtonPassSafariCompanionState(
                environment: "prod",
                credentials: ProtonPassSafariCredentials(
                    uid: "uid-1",
                    accessToken: "access-1",
                    refreshToken: "refresh-1",
                    userId: "user-1"
                )
            ),
            profileId: firstProfile,
            extensionId: firstContext.extensionId
        )
        try store.saveState(
            ProtonPassSafariCompanionState(
                environment: "prod",
                credentials: ProtonPassSafariCredentials(
                    uid: "uid-2",
                    accessToken: "access-2",
                    refreshToken: "refresh-2",
                    userId: "user-2"
                )
            ),
            profileId: secondProfile,
            extensionId: secondContext.extensionId
        )

        let reply = await handle(
            adapter: adapter,
            context: firstContext,
            message: #"{"credentials":null}"#
        )

        XCTAssertNil(reply.error)
        XCTAssertNil(
            try store.loadState(profileId: firstProfile, extensionId: firstContext.extensionId)
        )
        XCTAssertNotNil(
            try store.loadState(profileId: secondProfile, extensionId: secondContext.extensionId)
        )
    }

    func testRefreshCredentialsUpdatesTokensAndPreservesIdentity() async throws {
        let store = InMemoryProtonPassSafariCompanionStore()
        let adapter = ProtonPassSafariApplicationIDAdapter(store: store)
        let context = try makeProtonContext(profileId: UUID())
        try store.saveState(
            ProtonPassSafariCompanionState(
                environment: "prod",
                credentials: ProtonPassSafariCredentials(
                    uid: "uid-1",
                    accessToken: "access-1",
                    refreshToken: "refresh-1",
                    userId: "user-1"
                )
            ),
            profileId: context.profileId,
            extensionId: context.extensionId
        )

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"refreshCredentials":{"AccessToken":"access-2","RefreshToken":"refresh-2"}}"#
        )

        XCTAssertNil(reply.error)
        let credentials = try XCTUnwrap(
            store.loadState(
                profileId: context.profileId,
                extensionId: context.extensionId
            )?.credentials
        )
        XCTAssertEqual(credentials.uid, "uid-1")
        XCTAssertEqual(credentials.userId, "user-1")
        XCTAssertEqual(credentials.accessToken, "access-2")
        XCTAssertEqual(credentials.refreshToken, "refresh-2")
    }

    func testRefreshCredentialsWithoutExistingCredentialsFails() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"refreshCredentials":{"AccessToken":"access","RefreshToken":"refresh"}}"#
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationSecureStateMissing.rawValue
        )
    }

    func testMalformedJSONFailsWithoutExposingPayload() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: "{not-json"
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationInvalidPayload.rawValue
        )
        XCTAssertFalse(error.localizedDescription.contains("not-json"))
    }

    func testUnknownMessageTypeFailsWithoutFakeSuccess() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"readFromClipboard":true}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedMessageType.rawValue
        )
    }

    func testDiagnosticsDoNotContainSensitiveValues() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: """
            {"credentials":{"UID":"uid-secret","AccessToken":"access-secret","RefreshToken":"refresh-secret","UserID":"user-secret"}}
            """
        )

        XCTAssertNil(reply.error)
        let description = String(describing: reply.value) + " " + String(describing: reply.error)
        XCTAssertFalse(description.contains("uid-secret"))
        XCTAssertFalse(description.contains("access-secret"))
        XCTAssertFalse(description.contains("refresh-secret"))
        XCTAssertFalse(description.contains("user-secret"))
    }

    private func handle(
        adapter: ProtonPassSafariApplicationIDAdapter,
        context: CompanionApplicationMessageContext,
        message: Any
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "protonCompanionReply")
        var replyValue: Any?
        var replyError: (any Error)?
        adapter.handle(
            request: CompanionApplicationMessageRequest(
                context: context,
                message: message
            )
        ) { value, error in
            replyValue = value
            replyError = error
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        return (replyValue, replyError)
    }

    private func makeProtonContext(
        profileId: UUID?
    ) throws -> CompanionApplicationMessageContext {
        let installed = try makeInstalledExtension(
            id: "ext-proton",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: ProtonNativeMessagingIdentifiers.safariHostBundleIdentifier,
                appexBundleID: ProtonNativeMessagingIdentifiers.safariExtensionBundleIdentifier
            )
        )
        return makeContext(installed: installed, profileId: profileId)
    }

    private func makeContext(
        installed: InstalledExtension,
        profileId: UUID? = nil
    ) -> CompanionApplicationMessageContext {
        CompanionApplicationMessageContext(
            applicationIdentifier: "application.id",
            extensionId: installed.id,
            profileId: profileId,
            installedExtension: installed
        )
    }
}
