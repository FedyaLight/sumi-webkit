import Foundation
import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewIdentityWitnessTests: XCTestCase {
    func testWitnessMatchesOnlyItsExactLiveWebView() {
        let webView = WKWebView()
        let otherWebView = WKWebView()
        let witness = WebViewIdentityWitness(webView)

        XCTAssertEqual(witness.identifier, ObjectIdentifier(webView))
        XCTAssertIdentical(witness.resolve(), webView)
        XCTAssertTrue(witness.matches(webView))
        XCTAssertFalse(witness.matches(otherWebView))
    }

    func testWitnessDoesNotKeepObjectAlive() {
        var object: NSObject? = NSObject()
        weak var observedObject = object
        let witness = WeakIdentityWitness(object!)

        object = nil

        XCTAssertNil(observedObject)
        XCTAssertNil(witness.resolve())
    }
}
