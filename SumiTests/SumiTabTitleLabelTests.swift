import AppKit
@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class SumiTabTitleLabelTests: XCTestCase {
    func testSidebarTitleHeightMatchesZenParityMetric() {
        XCTAssertEqual(SidebarRowLayout.titleHeight, 16)
    }

    func testNativeTitleLabelStaysInsideConstrainedSidebarRow() {
        let rowWidth: CGFloat = 220
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                Color.clear
                    .frame(width: SidebarRowLayout.faviconSize)
                    .padding(.leading, SidebarRowLayout.leadingInset)
                    .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

                SumiTabTitleLabel(
                    title: "A very long title that must truncate before the trailing action",
                    reservedTrailingWidth: SidebarRowLayout.trailingActionPadding,
                    animated: false
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(width: rowWidth, height: SidebarRowLayout.rowHeight)
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(
                        width: SidebarRowLayout.trailingActionSize,
                        height: SidebarRowLayout.trailingActionSize
                    )
                    .padding(.trailing, SidebarRowLayout.trailingInset)
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: SidebarRowLayout.rowHeight)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.fittingSize.width, rowWidth, accuracy: 1)
        XCTAssertEqual(host.fittingSize.height, SidebarRowLayout.rowHeight, accuracy: 1)
    }
}
