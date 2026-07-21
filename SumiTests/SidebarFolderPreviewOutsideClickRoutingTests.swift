import XCTest

@testable import Sumi

final class SidebarFolderPreviewOutsideClickRoutingTests: XCTestCase {
    func testClickInsideThePanelIsLeftAlone() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.decision(
                isPresented: true,
                phase: .down,
                isInsidePanel: true,
                hasPendingClose: false
            ),
            .ignore
        )
    }

    /// The panel may not be torn down between a sidebar row's mouse-down and
    /// mouse-up: ending the transient session re-renders every folder header,
    /// which drops the row's in-flight gesture.
    func testOutsideMouseDownArmsTheCloseWithoutTakingThePanelDown() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.decision(
                isPresented: true,
                phase: .down,
                isInsidePanel: false,
                hasPendingClose: false
            ),
            .closeAfterGesture
        )
    }

    func testArmedCloseFiresOnTheMatchingMouseUp() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.decision(
                isPresented: true,
                phase: .up,
                isInsidePanel: false,
                hasPendingClose: true
            ),
            .closeNow
        )
    }

    func testMouseUpWithoutAnArmedCloseDoesNothing() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.decision(
                isPresented: true,
                phase: .up,
                isInsidePanel: true,
                hasPendingClose: false
            ),
            .ignore
        )
    }

    /// A mouse-up inside the panel still completes an armed close: the press
    /// that armed it landed outside, and the pointer may have travelled since.
    func testArmedCloseIsNotCancelledByAMouseUpInsideThePanel() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.decision(
                isPresented: true,
                phase: .up,
                isInsidePanel: true,
                hasPendingClose: true
            ),
            .closeNow
        )
    }

    func testNothingIsRoutedWhileThePreviewIsDown() {
        for phase in [SidebarFolderPreviewPointerPhase.down, .up] {
            XCTAssertEqual(
                SidebarFolderPreviewOutsideClickRouting.decision(
                    isPresented: false,
                    phase: phase,
                    isInsidePanel: false,
                    hasPendingClose: true
                ),
                .ignore
            )
        }
    }

    /// The hover grace is on the same clock as a click, so it defers too.
    func testHoverGraceDefersWhileAButtonIsHeld() {
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.graceDecision(isMouseButtonHeld: true),
            .closeAfterGesture
        )
        XCTAssertEqual(
            SidebarFolderPreviewOutsideClickRouting.graceDecision(isMouseButtonHeld: false),
            .closeNow
        )
    }

    func testPendingCloseReasonsAreDistinct() {
        XCTAssertNotEqual(
            SidebarFolderPreviewPendingClose.outsideClick.reason,
            SidebarFolderPreviewPendingClose.hoverGrace.reason
        )
    }

    func testHitTestUsesTheReportedPanelFrame() {
        let panelFrame = CGRect(x: 300, y: 120, width: 250, height: 200)

        XCTAssertTrue(
            SidebarFolderPreviewOutsideClickRouting.isInsidePanel(
                swiftUIGlobalPoint: CGPoint(x: 320, y: 140),
                panelFrame: panelFrame
            )
        )
        XCTAssertFalse(
            SidebarFolderPreviewOutsideClickRouting.isInsidePanel(
                swiftUIGlobalPoint: CGPoint(x: 120, y: 140),
                panelFrame: panelFrame
            )
        )
    }

    /// Before the overlay reports a frame there is nothing to be inside of, so a
    /// click anywhere counts as outside and closes the panel.
    func testUnreportedPanelFrameTreatsEveryClickAsOutside() {
        XCTAssertFalse(
            SidebarFolderPreviewOutsideClickRouting.isInsidePanel(
                swiftUIGlobalPoint: .zero,
                panelFrame: nil
            )
        )
    }
}
