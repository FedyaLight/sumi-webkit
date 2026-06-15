import XCTest

@testable import Sumi

@MainActor
final class SumiDownloadPolicyTests: XCTestCase {
    func testCoreWebMIMENavigationIsNeverHijacked() {
        let identity = SumiDownloadContentIdentity.resolve(mimeType: "text/html", filename: "index.html")
        let handler = SumiContentHandlerRecord(
            contentType: "text/html",
            displayName: "HTML",
            handler: .alwaysAsk,
            applicationURL: nil
        )

        let action = SumiDownloadPolicyResolver.resolve(
            origin: .normalNavigation,
            identity: identity,
            handler: handler,
            fallback: .ask
        )

        XCTAssertEqual(action, .navigate)
    }

    func testDownloadClassifiedCoreWebMIMESavesWithoutPromptOrHandlerOpen() {
        let identity = SumiDownloadContentIdentity.resolve(mimeType: "text/html", filename: "index.html")
        let handler = SumiContentHandlerRecord(
            contentType: "text/html",
            displayName: "HTML",
            handler: .useSystemDefault,
            applicationURL: nil
        )

        let action = SumiDownloadPolicyResolver.resolve(
            origin: .responseForcedDownload,
            identity: identity,
            handler: handler,
            fallback: .ask
        )

        XCTAssertEqual(action, .saveFile)
    }

    func testExplicitUserSaveIgnoresHandlersAndFallbackPrompt() {
        let identity = SumiDownloadContentIdentity.resolve(mimeType: "application/pdf", filename: "paper.pdf")
        let handler = SumiContentHandlerRecord(
            contentType: "application/pdf",
            displayName: "PDF",
            handler: .useSystemDefault,
            applicationURL: nil
        )

        let action = SumiDownloadPolicyResolver.resolve(
            origin: .explicitUserSave,
            identity: identity,
            handler: handler,
            fallback: .ask
        )

        XCTAssertEqual(action, .saveFile)
    }

    func testPerTypeHandlerOverridesFallbackWithoutMutatingFallback() {
        let identity = SumiDownloadContentIdentity.resolve(mimeType: "application/pdf", filename: "paper.pdf")
        let handler = SumiContentHandlerRecord(
            contentType: "application/pdf",
            displayName: "PDF",
            handler: .saveFile,
            applicationURL: nil
        )

        let action = SumiDownloadPolicyResolver.resolve(
            origin: .responseForcedDownload,
            identity: identity,
            handler: handler,
            fallback: .ask
        )

        XCTAssertEqual(action, .saveFile)
    }

    func testUnknownFallbackAskOnlyPromptsEligibleDownloads() {
        let identity = SumiDownloadContentIdentity.resolve(mimeType: "application/octet-stream", filename: "archive.bin")

        XCTAssertEqual(
            SumiDownloadPolicyResolver.resolve(
                origin: .unshowableResponse,
                identity: identity,
                handler: nil,
                fallback: .ask
            ),
            .prompt(canPersistChoice: true)
        )
        XCTAssertEqual(
            SumiDownloadPolicyResolver.resolve(
                origin: .normalNavigation,
                identity: identity,
                handler: nil,
                fallback: .ask
            ),
            .navigate
        )
    }

    func testApplicationsStorePersistsRecordsAndRejectsHTML() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("DownloadApplications.json")
        let store = SumiDownloadApplicationsStore(fileURL: storeURL)

        store.upsert(SumiContentHandlerRecord(
            contentType: "application/pdf",
            displayName: "PDF",
            handler: .useSystemDefault,
            applicationURL: nil
        ))
        store.upsert(SumiContentHandlerRecord(
            contentType: "text/html",
            displayName: "HTML",
            handler: .alwaysAsk,
            applicationURL: nil
        ))

        let reloaded = SumiDownloadApplicationsStore(fileURL: storeURL)
        XCTAssertEqual(reloaded.record(for: "application/pdf")?.handler, .useSystemDefault)
        XCTAssertNil(reloaded.record(for: "text/html"))
    }

    func testDestinationResolverUsesCustomDirectoryIndependentlyFromFallback() {
        let custom = URL(fileURLWithPath: "/tmp/sumi-downloads", isDirectory: true)
        let preference = SumiDownloadDestinationPreference(
            alwaysAskWhereToSave: true,
            customDirectoryURL: custom
        )

        XCTAssertEqual(SumiDownloadDestinationResolver.defaultDirectory(preference: preference), custom)
    }
}
