import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class CompanionApplicationMessageRouterTests: XCTestCase {
    private final class FakeBackend: CompanionApplicationMessageBackend {
        let backendIdentifier = "test.companion"
        var supportedExtensionId: String
        var receivedContexts: [CompanionApplicationMessageContext] = []

        init(supportedExtensionId: String) {
            self.supportedExtensionId = supportedExtensionId
        }

        func supports(context: CompanionApplicationMessageContext) -> Bool {
            context.extensionId == supportedExtensionId
        }

        func handle(
            request: CompanionApplicationMessageRequest,
            replyHandler: (Any?, (any Error)?) -> Void
        ) {
            receivedContexts.append(request.context)
            replyHandler(["ok": true], nil)
        }
    }

    func testApplicationIdRoutesToScopedBackend() async throws {
        let profileId = UUID()
        let backend = FakeBackend(supportedExtensionId: "ext-supported")
        let router = CompanionApplicationMessageRouter(
            registry: CompanionApplicationBackendRegistry(backends: [backend])
        )
        let relay = makeRelay(router: router)
        let installed = try makeInstalledExtension(
            id: "ext-supported",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "application.id",
            message: "{\"environment\":\"prod\"}",
            profileId: profileId
        )

        XCTAssertEqual(reply.value as? [String: Bool], ["ok": true])
        XCTAssertNil(reply.error)
        XCTAssertEqual(backend.receivedContexts.first?.profileId, profileId)
        XCTAssertEqual(backend.receivedContexts.first?.extensionId, "ext-supported")
    }

    func testApplicationIdUnknownExtensionReturnsTypedUnsupportedBackend() async throws {
        let backend = FakeBackend(supportedExtensionId: "ext-supported")
        let router = CompanionApplicationMessageRouter(
            registry: CompanionApplicationBackendRegistry(backends: [backend])
        )
        let relay = makeRelay(router: router)
        let installed = try makeInstalledExtension(
            id: "ext-unknown",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "application.id",
            message: "{\"environment\":\"prod\"}"
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedBackend.rawValue
        )
        XCTAssertTrue(backend.receivedContexts.isEmpty)
    }

    func testUnsignedProtonBundleIdentifierSpoofDoesNotRouteToProtonBackend() async throws {
        let router = CompanionApplicationMessageRouter(
            registry: CompanionApplicationBackendRegistry(
                backends: [ProtonPassSafariApplicationIDAdapter()]
            )
        )
        let relay = makeRelay(router: router)
        let installed = try makeInstalledExtension(
            id: "ext-proton-spoof",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: ProtonNativeMessagingIdentifiers.safariHostBundleIdentifier,
                appexBundleID: ProtonNativeMessagingIdentifiers.safariExtensionBundleIdentifier
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "application.id",
            message: #"{"readFromClipboard":{}}"#
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedBackend.rawValue
        )
    }

    func testNonApplicationIdDoesNotRouteThroughCompanionRegistry() async throws {
        let backend = FakeBackend(supportedExtensionId: "ext-supported")
        let router = CompanionApplicationMessageRouter(
            registry: CompanionApplicationBackendRegistry(backends: [backend])
        )
        let relay = makeRelay(router: router)
        let installed = try makeInstalledExtension(
            id: "ext-supported",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host",
            message: ["type": "ping"]
        )

        XCTAssertNil(reply.value)
        XCTAssertTrue(backend.receivedContexts.isEmpty)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    private func makeRelay(
        router: CompanionApplicationMessageRouter
    ) -> SumiNativeMessagingRelay {
        SumiNativeMessagingRelay(
            launcher: MockHostLauncher(),
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: []),
            companionApplicationRouter: router
        )
    }

    private func sendMessageReply(
        relay: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String,
        message: Any,
        profileId: UUID? = nil
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingReply")
        var replyValue: Any?
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: installed.id,
            profileId: profileId,
            installedExtensions: [installed]
        ) { value, error in
            replyValue = value
            replyError = error
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        return (replyValue, replyError)
    }
}

@available(macOS 15.5, *)
@MainActor
final class MockHostLauncher: SumiHostApplicationLaunching {
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        _ = bundleIdentifier
        return URL(fileURLWithPath: "/Applications/Fixture.app")
    }

    func openApplication(withBundleIdentifier bundleIdentifier: String) async {
        _ = bundleIdentifier
    }
}

@available(macOS 15.5, *)
func makeInstalledExtension(
    id: String,
    sourceBundlePath: String,
    name: String = "Fixture"
) -> InstalledExtension {
    InstalledExtension(
        id: id,
        name: name,
        version: "1.0",
        manifestVersion: 3,
        description: nil,
        isEnabled: true,
        installDate: Date(),
        lastUpdateDate: Date(),
        packagePath: "/tmp/\(id)",
        iconPath: nil,
        sourceKind: .safariAppExtension,
        backgroundModel: .serviceWorker,
        incognitoMode: .split,
        sourcePathFingerprint: "fp",
        manifestRootFingerprint: "mf",
        sourceBundlePath: sourceBundlePath,
        optionsPagePath: nil,
        defaultPopupPath: nil,
        hasBackground: true,
        hasAction: true,
        hasOptionsPage: false,
        hasContentScripts: true,
        hasExtensionPages: true,
        activationSummary: ExtensionActivationSummary(
            matchPatternStrings: [],
            broadScope: false,
            hasContentScripts: true,
            hasAction: true,
            hasOptionsPage: false,
            hasExtensionPages: true
        ),
        manifest: [:]
    )
}

@available(macOS 15.5, *)
func makeFixtureApp(
    appBundleID: String,
    appexBundleID: String
) throws -> String {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SumiCompanion.\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Host.app", isDirectory: true)
    let appexURL = appURL
        .appendingPathComponent("Contents/PlugIns/Extension.appex", isDirectory: true)

    try FileManager.default.createDirectory(
        at: appexURL.appendingPathComponent("Contents", isDirectory: true),
        withIntermediateDirectories: true
    )

    try writePlist(
        ["CFBundleIdentifier": appBundleID],
        to: appURL.appendingPathComponent("Contents/Info.plist")
    )
    try writePlist(
        ["CFBundleIdentifier": appexBundleID],
        to: appexURL.appendingPathComponent("Contents/Info.plist")
    )
    return appexURL.path
}

func writePlist(_ dictionary: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(
        fromPropertyList: dictionary,
        format: .xml,
        options: 0
    )
    try data.write(to: url)
}
