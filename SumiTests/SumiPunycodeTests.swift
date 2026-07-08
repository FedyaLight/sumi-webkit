import XCTest

@testable import Sumi

/// Direct coverage for `SumiPunycode`, which is security-relevant for homograph
/// attacks: a host that visually resembles a trusted domain (via Cyrillic/Latin
/// look-alike glyphs, for example) must always be converted to an unambiguous
/// ASCII "xn--" form before it is used for any trust decision (address bar
/// classification, cookie/permission scoping, registrable-domain resolution).
///
/// Note on API surface: this module exposes only the *encode* direction
/// (`hostToASCII`, Unicode host -> ACE/"xn--" host). There is no punycode
/// *decode* API (ACE label -> Unicode) anywhere in `SumiURLCore`, so this suite
/// does not (and cannot) test decoding of hostile encoded labels — that surface
/// does not exist in the codebase. All "hostile input" coverage below instead
/// targets `hostToASCII` with adversarial/edge-case *Unicode* input, since that
/// is the only direction the shipped code exercises.
final class SumiPunycodeTests: XCTestCase {
    // MARK: - RFC 3492 round-trips (reference values cross-checked against
    // Python's standard-library `str.encode("punycode")`, an independent RFC
    // 3492 implementation).

    func testAllASCIIHostPassesThroughUnchanged() {
        XCTAssertEqual(SumiPunycode.hostToASCII("example.com"), "example.com")
        XCTAssertEqual(SumiPunycode.hostToASCII("sub.example.co.uk"), "sub.example.co.uk")
        XCTAssertEqual(SumiPunycode.hostToASCII("already-xn--label.com"), "already-xn--label.com")
    }

    func testASCIIHostIsLowercased() {
        XCTAssertEqual(SumiPunycode.hostToASCII("EXAMPLE.COM"), "example.com")
        XCTAssertEqual(SumiPunycode.hostToASCII("Sub.Example.COM"), "sub.example.com")
    }

    func testGermanUmlautLabelEncodesToKnownACEForm() {
        XCTAssertEqual(SumiPunycode.hostToASCII("münchen.com"), "xn--mnchen-3ya.com")
        XCTAssertEqual(SumiPunycode.hostToASCII("bücher.example"), "xn--bcher-kva.example")
        XCTAssertEqual(SumiPunycode.hostToASCII("über.com"), "xn--ber-goa.com")
    }

    func testMixedCaseNonASCIIHostIsLoweredBeforeEncoding() {
        // hostToASCII lowercases the whole host up front, so an uppercase Unicode
        // label must encode identically to its already-lowercase form.
        XCTAssertEqual(SumiPunycode.hostToASCII("MÜNCHEN.COM"), SumiPunycode.hostToASCII("münchen.com"))
        XCTAssertEqual(SumiPunycode.hostToASCII("MÜNCHEN.COM"), "xn--mnchen-3ya.com")
    }

    func testMultiLabelInternationalizedHost() {
        XCTAssertEqual(SumiPunycode.hostToASCII("例子.测试"), "xn--fsqu00a.xn--0zwm56d")
    }

    func testEmojiLabelEncodesToKnownACEForm() {
        XCTAssertEqual(SumiPunycode.hostToASCII("💩.la"), "xn--ls8h.la")
    }

    // MARK: - Homograph attack: visually-confusable Cyrillic label must never
    // collide with the ASCII form of the domain it impersonates.

    func testCyrillicHomographOfAppleEncodesToDistinctACEForm() {
        // "аррle.com": Cyrillic а (U+0430) + Cyrillic р (U+0440) x2 + Latin "le",
        // rendered near-identically to "apple.com" in most UI fonts.
        let homograph = "\u{0430}\u{0440}\u{0440}le.com"
        let encoded = SumiPunycode.hostToASCII(homograph)

        XCTAssertEqual(encoded, "xn--le-6kc8da.com")
        // The whole point of punycoding before any trust decision: the encoded
        // form must be textually distinct from the real "apple.com", so any
        // string-equality-based allow-list or history match cannot conflate them.
        XCTAssertNotEqual(encoded, "apple.com")
        XCTAssertTrue(encoded?.hasPrefix("xn--") ?? false)
    }

    func testCyrillicOnlyLabelEncodesWithACEPrefix() throws {
        // Fully Cyrillic label (no Latin homoglyphs mixed in) still round-trips
        // through the ACE encoder rather than being passed through as "ASCII".
        let allCyrillic = "\u{043F}\u{0440}\u{0438}\u{043C}\u{0435}\u{0440}.com" // "пример.com"
        let encoded = try XCTUnwrap(SumiPunycode.hostToASCII(allCyrillic))
        XCTAssertTrue(encoded.hasPrefix("xn--"))
        XCTAssertTrue(encoded.unicodeScalars.allSatisfy { $0.isASCII })
    }

    // MARK: - Edge cases / hostile input must fail safely (return a value or nil),
    // never crash or hang.

    func testEmptyHostReturnsEmptyString() {
        XCTAssertEqual(SumiPunycode.hostToASCII(""), "")
    }

    func testHostOfOnlyDotsPassesThroughUnchanged() {
        XCTAssertEqual(SumiPunycode.hostToASCII("."), ".")
        XCTAssertEqual(SumiPunycode.hostToASCII(".."), "..")
    }

    func testEmptyLabelAdjacentToNonASCIILabelIsHandledSafely() {
        // "..münchen." -> labels ["", "", "münchen", ""]; empty labels are pure
        // ASCII (vacuously) and must not crash the encoder for the non-empty
        // internationalized label alongside them.
        XCTAssertEqual(SumiPunycode.hostToASCII("..münchen."), "..xn--mnchen-3ya.")
    }

    func testSingleNonASCIICharacterLabelDoesNotCrash() {
        XCTAssertNotNil(SumiPunycode.hostToASCII("é.com"))
    }

    func testLongNonASCIILabelDoesNotCrashOrHang() {
        let longLabel = String(repeating: "\u{00E9}", count: 300) // 300x "é"
        let result = SumiPunycode.hostToASCII("\(longLabel).com")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasSuffix(".com") ?? false)
    }

    func testRepeatedIdenticalNonASCIICodePointsDoesNotCrash() {
        // Degenerate input designed to stress the delta/bias adaptation loop
        // (every remaining code point equals `n` on the first pass).
        let label = String(repeating: "\u{4E2D}", count: 50) // 50x U+4E2D ("中")
        XCTAssertNotNil(SumiPunycode.hostToASCII(label))
    }
}
