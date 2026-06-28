@testable import Sumi
import XCTest

@MainActor
final class SumiDefaultBrowserServiceTests: XCTestCase {
    private let bundleURL = URL(fileURLWithPath: "/Applications/Sumi.app")

    func testCurrentStatusWhenSumiIsDefault() {
        let service = makeService(defaultApplicationURL: bundleURL)

        XCTAssertEqual(service.currentStatus(), .isDefault)
    }

    func testCurrentStatusWhenOtherAppIsDefault() {
        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let service = makeService(defaultApplicationURL: safariURL)

        XCTAssertEqual(service.currentStatus(), .other(displayName: "Safari"))
    }

    func testCurrentStatusWhenResolverReturnsNil() {
        let service = makeService(defaultApplicationURL: nil)

        XCTAssertEqual(service.currentStatus(), .unknown)
    }

    func testCurrentStatusWhenSandboxed() {
        let service = makeService(
            defaultApplicationURL: bundleURL,
            isSandboxed: true
        )

        XCTAssertEqual(service.currentStatus(), .sandboxed)
        XCTAssertFalse(service.canSetProgrammatically)
    }

    func testRequestBecomeDefaultUsesHttpSchemeOnly() async {
        let fakeWorkspace = FakeDefaultBrowserWorkspace()
        let service = makeService(workspace: fakeWorkspace)

        let result = await service.requestBecomeDefault()

        guard case .success = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(fakeWorkspace.setDefaultCalls.count, 1)
        XCTAssertEqual(fakeWorkspace.setDefaultCalls.first?.applicationURL, bundleURL)
        XCTAssertEqual(fakeWorkspace.setDefaultCalls.first?.urlScheme, "http")
    }

    func testRequestBecomeDefaultFailsWhenSandboxed() async {
        let fakeWorkspace = FakeDefaultBrowserWorkspace()
        let service = makeService(
            workspace: fakeWorkspace,
            isSandboxed: true
        )

        let result = await service.requestBecomeDefault()

        guard case .failure(.sandboxed) = result else {
            return XCTFail("Expected sandboxed failure, got \(result)")
        }
        XCTAssertTrue(fakeWorkspace.setDefaultCalls.isEmpty)
    }

    func testRequestBecomeDefaultMapsSystemError() async {
        let fakeWorkspace = FakeDefaultBrowserWorkspace()
        fakeWorkspace.setDefaultError = TestError.failed
        let service = makeService(workspace: fakeWorkspace)

        let result = await service.requestBecomeDefault()

        guard case .failure(.systemError(let message)) = result else {
            return XCTFail("Expected systemError, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testInfoPlistRegistersDefaultBrowserCapabilities() {
        let activityTypes = Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String]
        XCTAssertEqual(activityTypes?.contains("NSUserActivityTypeBrowsingWeb"), true)

        let documentTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
        let contentTypes = Set(
            (documentTypes ?? []).compactMap { $0["LSItemContentTypes"] as? [String] }.flatMap(\.self)
        )
        XCTAssertTrue(contentTypes.contains("public.html"))
        XCTAssertTrue(contentTypes.contains("public.xhtml"))
    }

    private func makeService(
        workspace: (any SumiDefaultBrowserWorkspaceResolving)? = nil,
        defaultApplicationURL: URL? = nil,
        isSandboxed: Bool = false
    ) -> SumiDefaultBrowserService {
        let resolvedWorkspace = workspace ?? FakeDefaultBrowserWorkspace(
            defaultApplicationURL: defaultApplicationURL
        )
        return SumiDefaultBrowserService(
            workspace: resolvedWorkspace,
            bundleURL: bundleURL,
            isSandboxed: { isSandboxed }
        )
    }
}

private enum TestError: Error {
    case failed
}

@MainActor
private final class FakeDefaultBrowserWorkspace: SumiDefaultBrowserWorkspaceResolving {
    struct SetDefaultCall: Equatable {
        let applicationURL: URL
        let urlScheme: String
    }

    var defaultApplicationURL: URL?
    var setDefaultCalls: [SetDefaultCall] = []
    var setDefaultError: Error?

    init(defaultApplicationURL: URL? = nil) {
        self.defaultApplicationURL = defaultApplicationURL
    }

    func urlForApplication(toOpen url: URL) -> URL? {
        _ = url
        return defaultApplicationURL
    }

    func setDefaultApplication(at applicationURL: URL, toOpenURLsWithScheme urlScheme: String) async throws {
        if let setDefaultError {
            throw setDefaultError
        }
        setDefaultCalls.append(
            SetDefaultCall(applicationURL: applicationURL, urlScheme: urlScheme)
        )
    }
}
