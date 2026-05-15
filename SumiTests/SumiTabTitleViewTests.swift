import AppKit
import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class SumiTabTitleViewTests: XCTestCase {
    func testTitleViewUsesClippingInsteadOfTailTruncation() {
        let view = makeView(width: 180)
        let fields = titleFields(in: view)

        XCTAssertEqual(fields.current.lineBreakMode, .byClipping)
        XCTAssertEqual(fields.previous.lineBreakMode, .byClipping)
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

        let maskLayer = try XCTUnwrap(fadeMaskLayer(in: view))
        XCTAssertEqual(maskLayer.frame.width, 160, accuracy: 0.01)
        XCTAssertEqual(maskLayer.startPoint.x, 0.675, accuracy: 0.001)
        XCTAssertEqual(maskLayer.endPoint.x, 0.875, accuracy: 0.001)
    }

    func testHoverChromeOnlyReservesFadePaddingWhenTrailingActionShows() {
        XCTAssertEqual(SidebarHoverChrome.trailingFadePadding(showsTrailingAction: false), 0)
        XCTAssertEqual(
            SidebarHoverChrome.trailingFadePadding(showsTrailingAction: true),
            SidebarRowLayout.trailingActionFadePadding
        )
    }

    func testSidebarTitleLineBoxHeightMatchesZenParityMetric() {
        XCTAssertEqual(SidebarRowLayout.titleLineBoxHeight, 16)
        XCTAssertEqual(SidebarRowLayout.titleHeight, SidebarRowLayout.titleLineBoxHeight)
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
        let fields = titleFields(in: view)

        XCTAssertEqual(fields.current.stringValue, "New Title")
        XCTAssertEqual(fields.previous.stringValue, "Old Title")
        XCTAssertNotNil(try XCTUnwrap(fields.previous.layer).animation(forKey: SumiTabTitleAnimation.fadeAndSlideOutKey))
        XCTAssertNotNil(try XCTUnwrap(fields.current.layer).animation(forKey: SumiTabTitleAnimation.slideInKey))
        XCTAssertNotNil(try XCTUnwrap(fields.current.layer).animation(forKey: SumiTabTitleAnimation.alphaKey))
    }

    func testNonAnimatedTitleUpdateClearsPreviousTitleState() throws {
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
            animated: false
        )

        let fields = titleFields(in: view)
        let previousLayer = try XCTUnwrap(fields.previous.layer)
        let currentLayer = try XCTUnwrap(fields.current.layer)

        XCTAssertEqual(fields.current.stringValue, "New Title")
        XCTAssertEqual(fields.previous.stringValue, "")
        XCTAssertEqual(fields.previous.alphaValue, 0, accuracy: 0.001)
        XCTAssertEqual(previousLayer.opacity, 0, accuracy: 0.001)
        XCTAssertNil(previousLayer.animation(forKey: SumiTabTitleAnimation.fadeAndSlideOutKey))
        XCTAssertNil(currentLayer.animation(forKey: SumiTabTitleAnimation.slideInKey))
        XCTAssertNil(currentLayer.animation(forKey: SumiTabTitleAnimation.alphaKey))
    }

    func testTitleViewStartsLoadingShimmerAnimation() throws {
        let view = makeView(width: 200)

        view.apply(
            title: "Loading Title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 0,
            animated: false,
            isLoading: true
        )
        view.layoutSubtreeIfNeeded()

        let maskLayer = try XCTUnwrap(loadingShimmerMaskLayer(in: view))
        let animation = try XCTUnwrap(maskLayer.animation(forKey: SumiTabTitleAnimation.loadingShimmerKey))

        XCTAssertEqual(
            maskLayer.bounds.width,
            200,
            accuracy: 0.001
        )
        XCTAssertEqual(animation.duration, SumiTabTitleAnimation.loadingShimmerCycleDuration, accuracy: 0.001)
        let locationsAnimation = try XCTUnwrap(animation as? CABasicAnimation)
        XCTAssertEqual(locationsAnimation.keyPath, "locations")
        XCTAssertEqual(maskLayer.colors?.count, 5)
        assertDoubles(maskLayer.locations?.map(\.doubleValue), equalTo: [-0.72, -0.5616, -0.36, -0.1584, 0])
        assertDoubles(
            (locationsAnimation.toValue as? [NSNumber])?.map(\.doubleValue),
            equalTo: [1, 1.1584, 1.36, 1.5616, 1.72]
        )
    }

    func testTitleViewStopsLoadingShimmerAnimation() throws {
        let view = makeView(width: 200)

        view.apply(
            title: "Loading Title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 0,
            animated: false,
            isLoading: true
        )
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(loadingShimmerMaskLayer(in: view)?.animation(forKey: SumiTabTitleAnimation.loadingShimmerKey))

        view.apply(
            title: "Loading Title",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            fadeWidth: 32,
            trailingFadePadding: 0,
            animated: false,
            isLoading: false
        )

        XCTAssertNil(loadingShimmerMaskLayer(in: view))
    }

    func testSwiftUIHostedLabelKeepsFullWidthWithOverlaidAction() throws {
        let host = NSHostingView(
            rootView: ZStack(alignment: .trailing) {
                SumiTabTitleLabel(
                    title: "A very long hosted tab title",
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: .primary,
                    fadeWidth: 32,
                    trailingFadePadding: SidebarRowLayout.trailingActionFadePadding,
                    animated: false,
                    height: SidebarRowLayout.titleHeight
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: SidebarRowLayout.trailingActionSize, height: SidebarRowLayout.titleHeight)
                    .padding(.trailing, SidebarRowLayout.trailingInset)
            }
            .frame(width: 120, height: SidebarRowLayout.titleHeight)
        )
        host.frame = NSRect(x: 0, y: 0, width: 120, height: SidebarRowLayout.titleHeight)
        host.layoutSubtreeIfNeeded()

        let titleView = try XCTUnwrap(findSubview(ofType: SumiTabTitleView.self, in: host))
        XCTAssertEqual(titleView.frame.width, 120, accuracy: 1.0)

        let maskLayer = try XCTUnwrap(fadeMaskLayer(in: titleView))
        XCTAssertEqual(maskLayer.frame.width, titleView.bounds.width, accuracy: 0.5)
        XCTAssertEqual(
            maskLayer.endPoint.x,
            (titleView.bounds.width - SidebarRowLayout.trailingActionFadePadding) / titleView.bounds.width,
            accuracy: 0.001
        )
    }

    func testSwiftUIHostedLabelStaysVerticallyCenteredInSidebarRow() throws {
        let host = NSHostingView(
            rootView: HStack(spacing: 0) {
                SumiTabTitleLabel(
                    title: "Subscriptions - YouTube",
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: .primary,
                    animated: false,
                    height: SidebarRowLayout.titleHeight
                )
                .frame(height: SidebarRowLayout.titleHeight, alignment: .center)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 180, height: SidebarRowLayout.rowHeight, alignment: .center)
        )
        host.frame = NSRect(x: 0, y: 0, width: 180, height: SidebarRowLayout.rowHeight)
        host.layoutSubtreeIfNeeded()

        let titleView = try XCTUnwrap(findSubview(ofType: SumiTabTitleView.self, in: host))
        let titleFrameInHost = titleView.convert(titleView.bounds, to: host)
        XCTAssertEqual(titleFrameInHost.height, SidebarRowLayout.titleHeight, accuracy: 0.5)
        XCTAssertEqual(titleFrameInHost.midY, SidebarRowLayout.rowHeight / 2, accuracy: 1.0)
    }

    private func makeView(width: CGFloat) -> SumiTabTitleView {
        let view = SumiTabTitleView(frame: NSRect(x: 0, y: 0, width: width, height: SidebarRowLayout.titleHeight))
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

    private func titleFields(in view: SumiTabTitleView) -> (previous: NSTextField, current: NSTextField) {
        let fields = textFields(in: view)
        XCTAssertGreaterThanOrEqual(fields.count, 2)
        return (fields[0], fields[1])
    }

    private func textFields(in view: SumiTabTitleView) -> [NSTextField] {
        view.subviews.compactMap { $0 as? NSTextField }
    }

    private func fadeMaskLayer(in view: SumiTabTitleView) -> CAGradientLayer? {
        view.layer?.mask as? CAGradientLayer
    }

    private func loadingShimmerMaskLayer(in view: SumiTabTitleView) -> CAGradientLayer? {
        titleFields(in: view).current.layer?.mask as? CAGradientLayer
    }

    private func assertDoubles(
        _ actual: [Double]?,
        equalTo expected: [Double],
        accuracy: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected non-nil values", file: file, line: line)
            return
        }

        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: accuracy, file: file, line: line)
        }
    }
}
