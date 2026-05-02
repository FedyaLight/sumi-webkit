import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarAudioHitExclusionTests: XCTestCase {
    func testFixedRectExclusionOnlyContainsItsFrame() {
        let zone = SidebarDragSourceExclusionZone.fixedRect(
            CGRect(x: 38, y: 7, width: 22, height: 22)
        )
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 36)

        XCTAssertTrue(zone.contains(CGPoint(x: 39, y: 18), in: bounds))
        XCTAssertTrue(zone.contains(CGPoint(x: 58, y: 28), in: bounds))
        XCTAssertFalse(zone.contains(CGPoint(x: 37, y: 18), in: bounds))
        XCTAssertFalse(zone.contains(CGPoint(x: 61, y: 18), in: bounds))
        XCTAssertFalse(zone.contains(CGPoint(x: 39, y: 6), in: bounds))
        XCTAssertFalse(zone.contains(CGPoint(x: 39, y: 30), in: bounds))
    }

    func testShortcutLiveAudioExclusionProtectsMuteButtonWithoutResetAffordance() {
        let zones = makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: .liveBackgrounded,
            dragHasTrailingActionExclusion: true,
            hasLiveAudioExclusion: true
        )
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 36)

        XCTAssertTrue(contains(CGPoint(x: 39, y: 18), in: zones, bounds: bounds))
        XCTAssertFalse(contains(CGPoint(x: 37, y: 18), in: zones, bounds: bounds))
        XCTAssertFalse(contains(CGPoint(x: 61, y: 18), in: zones, bounds: bounds))
        XCTAssertTrue(contains(CGPoint(x: 181, y: 18), in: zones, bounds: bounds))
    }

    func testShortcutLiveAudioExclusionProtectsMuteButtonWithResetAffordance() {
        let zones = makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: .driftedLiveBackgrounded,
            dragHasTrailingActionExclusion: true,
            hasLiveAudioExclusion: true
        )
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 36)

        XCTAssertTrue(contains(CGPoint(x: 55, y: 18), in: zones, bounds: bounds))
        XCTAssertTrue(contains(CGPoint(x: 70, y: 18), in: zones, bounds: bounds))
        XCTAssertFalse(contains(CGPoint(x: 73, y: 18), in: zones, bounds: bounds))
        XCTAssertTrue(contains(CGPoint(x: 20, y: 18), in: zones, bounds: bounds))
    }

    func testShortcutRowDoesNotReserveAudioAreaWhenNoLiveAudioButtonIsShown() {
        let zones = makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: .liveBackgrounded,
            dragHasTrailingActionExclusion: true,
            hasLiveAudioExclusion: false
        )
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 36)

        XCTAssertFalse(contains(CGPoint(x: 39, y: 18), in: zones, bounds: bounds))
    }

    private func contains(
        _ point: CGPoint,
        in zones: [SidebarDragSourceExclusionZone],
        bounds: CGRect
    ) -> Bool {
        zones.contains { $0.contains(point, in: bounds) }
    }
}
