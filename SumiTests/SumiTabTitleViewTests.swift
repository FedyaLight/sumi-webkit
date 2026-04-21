import AppKit
import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class SumiTabTitleViewTests: XCTestCase {
    func testTitleViewUsesClippingInsteadOfTailTruncation() {
        let view = makeView(width: 180)

        XCTAssertEqual(view.currentTitleField.lineBreakMode, .byClipping)
        XCTAssertEqual(view.previousTitleField.lineBreakMode, .byClipping)
    }

    func testTitleViewAppliesTrailingFadeMask() throws {
        let view = makeView(width: 160)

        view.apply(
            title: "A long tab title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 20,
            animated: false
        )

        let maskLayer = try XCTUnwrap(view.fadeMaskLayer)
        XCTAssertEqual(maskLayer.frame.width, 160, accuracy: 0.01)
        XCTAssertEqual(maskLayer.startPoint.x, 0.675, accuracy: 0.001)
        XCTAssertEqual(maskLayer.endPoint.x, 0.875, accuracy: 0.001)
    }

    func testTitleViewAnimatesPreviousAndCurrentTitleDuringTransition() throws {
        let view = makeView(width: 200)
        view.apply(
            title: "Old Title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 0,
            animated: false
        )

        view.apply(
            title: "New Title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 0,
            animated: true
        )

        XCTAssertEqual(view.currentTitleField.stringValue, "New Title")
        XCTAssertEqual(view.previousTitleField.stringValue, "Old Title")
        XCTAssertNotNil(try XCTUnwrap(view.previousTitleField.layer).animation(forKey: SumiTabTitleAnimation.fadeAndSlideOutKey))
        XCTAssertNotNil(try XCTUnwrap(view.currentTitleField.layer).animation(forKey: SumiTabTitleAnimation.slideInKey))
        XCTAssertNotNil(try XCTUnwrap(view.currentTitleField.layer).animation(forKey: SumiTabTitleAnimation.fadeInKey))
    }

    func testSwiftUIHostedLabelUsesContainerWidthForMaskLayout() throws {
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                SumiTabTitleLabel(
                    title: "A very long hosted tab title",
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: .primary,
                    fadeWidth: 32,
                    trailingFadePadding: 0,
                    animated: false
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: 24, height: 16)
            }
            .frame(width: 120, height: 16)
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        host.layoutSubtreeIfNeeded()

        let titleView = try XCTUnwrap(findSubview(ofType: SumiTabTitleView.self, in: host))
        XCTAssertEqual(titleView.frame.width, 96, accuracy: 1.0)

        let maskLayer = try XCTUnwrap(titleView.fadeMaskLayer)
        XCTAssertEqual(maskLayer.frame.width, titleView.bounds.width, accuracy: 0.5)
    }

    private func makeView(width: CGFloat) -> SumiTabTitleView {
        let view = SumiTabTitleView(frame: NSRect(x: 0, y: 0, width: width, height: 16))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func findSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let view = view as? T {
            return view
        }

        for subview in view.subviews {
            if let match = findSubview(ofType: type, in: subview) {
                return match
            }
        }

        return nil
    }
}
