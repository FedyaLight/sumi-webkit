import AppKit
@testable import Sumi
import XCTest

@MainActor
final class WebKitTransientChromeInteractionShieldOwnerTests: XCTestCase {
    func testSuppressingAppliesScriptRefreshesTrackingAndClearsHoveredLink() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            currentClientPoint: { CGPoint(x: 12, y: 34) },
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])

        XCTAssertTrue(owner.isMouseTrackingSuppressed)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(clearHoveredLinkCount, 1)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("shield.setActive(true"))
        XCTAssertTrue(scripts[0].contains("clientX: 12.0"))
    }

    func testSuppressionExemptionKeepsShieldInactive() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            isSuppressionExempt: { true },
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])

        XCTAssertFalse(owner.isMouseTrackingSuppressed)
        XCTAssertTrue(scripts.isEmpty)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(clearHoveredLinkCount, 0)
    }

    func testRectChangeReappliesScriptWithoutRefreshingMouseTrackingState() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])
        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 5, y: 6, width: 7, height: 8),
        ])

        XCTAssertTrue(owner.isMouseTrackingSuppressed)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(clearHoveredLinkCount, 1)
        XCTAssertTrue(scripts[1].contains("left: 5.0"))
    }

    private func makeOwner(
        isSuppressionExempt: @escaping @MainActor () -> Bool = { false },
        currentClientPoint: @escaping @MainActor () -> CGPoint? = { nil },
        evaluateJavaScript: @escaping @MainActor (String) -> Void = { _ in },
        refreshPointerPresentation: @escaping @MainActor () -> Void = {},
        clearHoveredLink: @escaping @MainActor () -> Void = {}
    ) -> WebKitTransientChromeInteractionShieldOwner {
        WebKitTransientChromeInteractionShieldOwner(
            isSuppressionExempt: isSuppressionExempt,
            currentClientPoint: currentClientPoint,
            evaluateJavaScript: evaluateJavaScript,
            refreshPointerPresentation: refreshPointerPresentation,
            clearHoveredLink: clearHoveredLink
        )
    }
}
