import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ProtonPassSafariApplicationIDAdapterTests: XCTestCase {
    func testRejectsUnsignedBundleWithProtonBundleIdentifiers() throws {
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

        XCTAssertFalse(adapter.supports(context: context))
    }

    func testRejectsSignedNonProtonIdentity() throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let installed = try makeInstalledExtension(
            id: "ext-non-proton-signed",
            sourceBundlePath: Bundle.main.bundleURL.path,
            name: "Signed Non Proton"
        )
        let context = makeContext(installed: installed)

        XCTAssertFalse(adapter.supports(context: context))
    }

    func testSupportsInstalledSignedProtonSafariExtensionWhenPresent() throws {
        let appexURL = URL(
            fileURLWithPath: "/Applications/Proton Pass for Safari.app/Contents/PlugIns/Safari Extension.appex",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            throw XCTSkip("Proton Pass for Safari is not installed")
        }

        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let installed = try makeInstalledExtension(
            id: "ext-proton-installed",
            sourceBundlePath: appexURL.path,
            name: "Installed Proton"
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

    func testReadFromClipboardReturnsRawStringFromClipboardReader() async throws {
        let clipboard = FakeProtonPassSafariClipboard(value: "copied-secret")
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: clipboard
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"readFromClipboard":{}}"#
        )

        XCTAssertEqual(reply.value as? String, "copied-secret")
        XCTAssertNil(reply.error)
        XCTAssertEqual(clipboard.readCount, 1)
    }

    func testReadFromClipboardEmptyPasteboardReturnsEmptyString() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: FakeProtonPassSafariClipboard(value: nil)
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"readFromClipboard":{}}"#
        )

        XCTAssertEqual(reply.value as? String, "")
        XCTAssertNil(reply.error)
    }

    func testReadFromClipboardRequiresObjectPayload() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: FakeProtonPassSafariClipboard(value: "copied-secret")
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"readFromClipboard":"copied-secret"}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationInvalidPayload.rawValue
        )
        XCTAssertFalse(String(describing: error.userInfo).contains("copied-secret"))
        assertNoSensitiveMetadata(in: error.userInfo)
    }

    func testReadFromClipboardHandledDiagnosticsDoNotExposeClipboardContent() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: FakeProtonPassSafariClipboard(value: "copied-secret")
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"readFromClipboard":{}}"#
        )

        XCTAssertNil(reply.error)
        let shape = ProtonPassSafariApplicationIDAdapter.sanitizedMessageShape(
            for: #"{"readFromClipboard":{}}"#
        )
        let handledLine = ProtonPassSafariApplicationIDAdapter.handledMessageLogLine(
            context: context,
            shape: shape
        )
        XCTAssertTrue(handledLine.contains("ProtonCompanionHandled"))
        XCTAssertTrue(handledLine.contains("selectedType=readFromClipboard"))
        XCTAssertTrue(handledLine.contains("result=success"))
        XCTAssertFalse(handledLine.contains("ProtonCompanionUnsupported"))
        XCTAssertFalse(handledLine.contains("copied-secret"))
    }

    func testWriteToClipboardWritesContentWithoutReturningIt() async throws {
        let clipboard = FakeProtonPassSafariClipboard(value: nil)
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: clipboard
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"writeToClipboard":{"Content":"copied-secret"}}"#
        )

        XCTAssertNil(reply.value)
        XCTAssertNil(reply.error)
        XCTAssertEqual(clipboard.writtenStrings, ["copied-secret"])
    }

    func testWriteToClipboardRequiresContentString() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore(),
            clipboard: FakeProtonPassSafariClipboard(value: nil)
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"writeToClipboard":{"Content":42}}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationInvalidPayload.rawValue
        )
        XCTAssertEqual(error.userInfo["SumiCompanionSelectedType"] as? String, "writeToClipboard")
        assertNoSensitiveMetadata(in: error.userInfo)
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
        XCTAssertEqual(error.userInfo["SumiCompanionPayloadClass"] as? String, "String")
        XCTAssertEqual(error.userInfo["SumiCompanionParseMode"] as? String, "invalidJSONString")
        XCTAssertEqual(error.userInfo["SumiCompanionTopLevelKeys"] as? [String], [])
        XCTAssertEqual(
            error.userInfo["SumiCompanionParseFailureReason"] as? String,
            "invalidJSONString"
        )
        assertNoSensitiveMetadata(in: error.userInfo)
    }

    func testMessageShapeSanitizerReportsJSONShapeWithoutValues() {
        let shape = ProtonPassSafariApplicationIDAdapter.sanitizedMessageShape(
            for:
                """
                {"credentials":{"UID":"uid-secret","AccessToken":"access-secret","RefreshToken":"refresh-secret","UserID":"user-secret"}}
                """
        )

        XCTAssertEqual(shape.payloadClass, "String")
        XCTAssertEqual(shape.encoding, "jsonString")
        XCTAssertEqual(shape.parseMode, "jsonString")
        XCTAssertEqual(shape.topLevelKeys, ["credentials"])
        XCTAssertEqual(shape.selectedType, "credentials")
        XCTAssertEqual(shape.keysForLog, "[credentials]")
        XCTAssertFalse(shape.keysForLog.contains("uid-secret"))
        XCTAssertFalse(shape.keysForLog.contains("access-secret"))
        XCTAssertFalse(shape.keysForLog.contains("refresh-secret"))
        XCTAssertFalse(shape.keysForLog.contains("user-secret"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("uid-secret"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("access-secret"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("refresh-secret"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("user-secret"))
    }

    func testMessageShapeSanitizerReportsDoubleEncodedJSONShapeWithoutValues() throws {
        let inner = #"{"readFromClipboard":"clipboard-secret"}"#
        let data = try JSONSerialization.data(withJSONObject: inner, options: [.fragmentsAllowed])
        let outer = try XCTUnwrap(String(data: data, encoding: .utf8))

        let shape = ProtonPassSafariApplicationIDAdapter.sanitizedMessageShape(for: outer)

        XCTAssertEqual(shape.payloadClass, "String")
        XCTAssertEqual(shape.encoding, "doubleEncodedJSONString")
        XCTAssertEqual(shape.topLevelKeys, ["readFromClipboard"])
        XCTAssertEqual(shape.selectedType, "readFromClipboard")
        XCTAssertFalse(shape.keysForLog.contains("clipboard-secret"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("clipboard-secret"))
    }

    func testMessageShapeSanitizerReportsObjectShapeWithoutValues() {
        let shape = ProtonPassSafariApplicationIDAdapter.sanitizedMessageShape(
            for: [
                "fetchRelatedOrigins": [
                    "url": "https://example.com/.well-known/webauthn?secret=value",
                ],
            ]
        )

        XCTAssertEqual(shape.payloadClass, "Dictionary")
        XCTAssertEqual(shape.encoding, "object")
        XCTAssertEqual(shape.topLevelKeys, ["fetchRelatedOrigins"])
        XCTAssertEqual(shape.selectedType, "fetchRelatedOrigins")
        XCTAssertFalse(shape.keysForLog.contains("example.com"))
        XCTAssertFalse(shape.keysForLog.contains("secret=value"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("example.com"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("secret=value"))
        XCTAssertFalse(String(describing: shape.errorUserInfo).contains("https://"))
    }

    func testUnsupportedKnownButUnimplementedKeyReturnsShapeMetadata() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"fetchRelatedOrigins":{"url":"https://example.com/login?token=secret#frag"}}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedMessageType.rawValue
        )
        XCTAssertEqual(
            error.localizedDescription,
            "The companion application message type is unsupported."
        )
        XCTAssertEqual(error.userInfo["SumiCompanionPayloadClass"] as? String, "String")
        XCTAssertEqual(error.userInfo["SumiCompanionParseMode"] as? String, "jsonString")
        XCTAssertEqual(error.userInfo["SumiCompanionTopLevelKeys"] as? [String], ["fetchRelatedOrigins"])
        XCTAssertEqual(error.userInfo["SumiCompanionSelectedType"] as? String, "fetchRelatedOrigins")
        assertNoSensitiveMetadata(in: error.userInfo)

        let logLine = ProtonPassSafariApplicationIDAdapter.unsupportedMessageLogLine(
            context: context,
            shape: ProtonPassSafariApplicationIDAdapter.sanitizedMessageShape(
                for: #"{"fetchRelatedOrigins":{"url":"https://example.com/login?token=secret#frag"}}"#
            )
        )
        XCTAssertTrue(logLine.contains("ProtonCompanionUnsupported"))
        XCTAssertTrue(logLine.contains("topLevelKeys=[fetchRelatedOrigins]"))
        XCTAssertTrue(logLine.contains("selectedType=fetchRelatedOrigins"))
        XCTAssertFalse(logLine.contains("example.com"))
        XCTAssertFalse(logLine.contains("token=secret"))
        XCTAssertFalse(logLine.contains("#frag"))
    }

    func testUnknownMessageTypeReturnsShapeMetadataWithoutFakeSuccess() async throws {
        let adapter = ProtonPassSafariApplicationIDAdapter(
            store: InMemoryProtonPassSafariCompanionStore()
        )
        let context = try makeProtonContext(profileId: UUID())

        let reply = await handle(
            adapter: adapter,
            context: context,
            message: #"{"unknownSecretKey":"secret-value"}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedMessageType.rawValue
        )
        XCTAssertEqual(error.userInfo["SumiCompanionTopLevelKeys"] as? [String], ["unknownSecretKey"])
        XCTAssertNil(error.userInfo["SumiCompanionSelectedType"])
        XCTAssertFalse(String(describing: error.userInfo).contains("secret-value"))
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

    private func assertNoSensitiveMetadata(
        in userInfo: [AnyHashable: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let description = String(describing: userInfo)
        for forbidden in [
            "uid-secret",
            "access-secret",
            "refresh-secret",
            "user-secret",
            "copied-secret",
            "AccessToken",
            "RefreshToken",
            "UID",
            "UserID",
            "clipboard-secret",
            "https://example.com",
            "example.com",
            "token=secret",
            "#frag",
        ] {
            XCTAssertFalse(
                description.contains(forbidden),
                "Metadata exposed forbidden value \(forbidden)",
                file: file,
                line: line
            )
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class FakeProtonPassSafariClipboard: ProtonPassSafariClipboardAccessing {
    private let value: String?
    private(set) var readCount = 0
    private(set) var writtenStrings: [String] = []

    init(value: String?) {
        self.value = value
    }

    func readString() -> String? {
        readCount += 1
        return value
    }

    func writeString(_ string: String) -> Bool {
        writtenStrings.append(string)
        return true
    }
}
