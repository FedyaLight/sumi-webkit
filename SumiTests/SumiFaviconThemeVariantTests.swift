import Foundation
import XCTest
@testable import Sumi

final class SumiFaviconThemeVariantTests: XCTestCase {
    func testCachedSVGIsReusedWhileItsDocumentCandidateRemainsActive() throws {
        let fixture = try makeFixture()

        XCTAssertTrue(
            SumiFaviconSelectionPolicy.shouldUseCachedSelection(
                fixture.selection,
                over: [fixture.candidate(sourceURL: fixture.cachedSourceURL)]
            )
        )
    }

    func testCachedSVGIsReplacedWhenDocumentSwitchesThemeVariantURL() throws {
        let fixture = try makeFixture()
        let replacementURL = try XCTUnwrap(URL(string: "https://assets.example/favicon.svg"))

        XCTAssertFalse(
            SumiFaviconSelectionPolicy.shouldUseCachedSelection(
                fixture.selection,
                over: [fixture.candidate(sourceURL: replacementURL)]
            )
        )
    }

    func testCachedTouchIconIsReplacedWhenDocumentFaviconIsPreferred() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://x.example/"))
        let faviconURL = try XCTUnwrap(URL(string: "https://x.example/favicon.ico"))
        let touchIconURL = try XCTUnwrap(URL(string: "https://x.example/apple-touch-icon.png"))
        let partition = SumiFaviconPartition.regular()
        let cachedTouchIcon = SumiStoredFaviconSelection(
            partition: partition,
            pageURL: pageURL,
            sourceURL: touchIconURL,
            blobID: "touch-icon",
            revision: "touch-icon",
            payloadKind: .png,
            mimeType: "image/png",
            pixelWidth: 192,
            pixelHeight: 192,
            sourceKind: .documentLink,
            declaredSizes: [SumiFaviconDeclaredSize(width: 192, height: 192)],
            declaredType: "image/png",
            purposes: [.any],
            updatedAt: Date()
        )
        let candidates = [
            SumiFaviconCandidate(
                pageURL: pageURL,
                iconURL: faviconURL,
                sourceKind: .documentLink,
                relTokens: ["icon"],
                declaredType: "image/x-icon",
                partition: partition
            ),
            SumiFaviconCandidate(
                pageURL: pageURL,
                iconURL: touchIconURL,
                sourceKind: .documentLink,
                relTokens: ["apple-touch-icon"],
                declaredSizes: [SumiFaviconDeclaredSize(width: 192, height: 192)],
                declaredType: "image/png",
                sourcePriority: 1,
                partition: partition
            ),
        ]

        XCTAssertFalse(
            SumiFaviconSelectionPolicy.shouldUseCachedSelection(
                cachedTouchIcon,
                over: candidates
            )
        )
    }

    private func makeFixture() throws -> FaviconThemeVariantFixture {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let cachedSourceURL = try XCTUnwrap(URL(string: "https://assets.example/favicon-dark.svg"))
        let partition = SumiFaviconPartition.regular()
        let selection = SumiStoredFaviconSelection(
            partition: partition,
            pageURL: pageURL,
            sourceURL: cachedSourceURL,
            blobID: "blob",
            revision: "revision",
            payloadKind: .svg,
            mimeType: "image/svg+xml",
            pixelWidth: nil,
            pixelHeight: nil,
            sourceKind: .documentLink,
            declaredSizes: [],
            declaredType: "image/svg+xml",
            purposes: [.any],
            updatedAt: Date()
        )
        return FaviconThemeVariantFixture(
            pageURL: pageURL,
            cachedSourceURL: cachedSourceURL,
            partition: partition,
            selection: selection
        )
    }
}

private struct FaviconThemeVariantFixture {
    let pageURL: URL
    let cachedSourceURL: URL
    let partition: SumiFaviconPartition
    let selection: SumiStoredFaviconSelection

    func candidate(sourceURL: URL) -> SumiFaviconCandidate {
        SumiFaviconCandidate(
            pageURL: pageURL,
            iconURL: sourceURL,
            sourceKind: .documentLink,
            relTokens: ["icon"],
            declaredType: "image/svg+xml",
            partition: partition
        )
    }
}
