//
//  SumiEmojiCatalogTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

final class SumiEmojiCatalogTests: XCTestCase {
    private static func flagRegionCode(from glyph: String) -> String? {
        let scalars = Array(glyph.unicodeScalars)
        guard scalars.count == 2 else { return nil }

        let asciiScalars = scalars.compactMap { scalar -> UnicodeScalar? in
            let value = scalar.value
            guard (0x1F1E6...0x1F1FF).contains(value) else { return nil }
            return UnicodeScalar(value - 0x1F1E6 + 65)
        }
        guard asciiScalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(asciiScalars))
    }

    func testCatalogExcludesStandaloneRegionalIndicators() {
        for entry in SumiEmojiCatalog.allEntries {
            let scalars = Array(entry.glyph.unicodeScalars)
            if scalars.count == 1 {
                let v = scalars[0].value
                XCTAssertFalse(
                    (0x1F1E6...0x1F1FF).contains(v),
                    "Standalone regional indicator should not appear: U+\(String(v, radix: 16, uppercase: true))"
                )
            }
        }
    }

    func testCatalogContainsGrinningFace() {
        XCTAssertTrue(
            SumiEmojiCatalog.allEntries.contains { $0.glyph == "😀" },
            "Expected basic smiley in catalog"
        )
    }

    func testCatalogContainsFlagPair() {
        let usFlag = "\u{1F1FA}\u{1F1F8}"
        XCTAssertTrue(
            SumiEmojiCatalog.allEntries.contains { $0.glyph == usFlag },
            "Expected composite flag glyph"
        )
    }

    func testEntriesMatchingFiltersByUnicodeName() {
        let entries = SumiEmojiCatalog.allEntries
        let grinMatches = SumiEmojiCatalog.entries(matching: "grinning face", in: entries)
        XCTAssertTrue(grinMatches.contains { $0.glyph == "😀" })
    }

    func testEntriesMatchingEmptyQueryReturnsAll() {
        let entries = SumiEmojiCatalog.allEntries
        XCTAssertEqual(SumiEmojiCatalog.entries(matching: "", in: entries).count, entries.count)
        XCTAssertEqual(SumiEmojiCatalog.entries(matching: "   ", in: entries).count, entries.count)
    }

    func testCatalogEntryIdsAreUnique() {
        let entries = SumiEmojiCatalog.allEntries
        var seen = Set<String>()
        for entry in entries {
            XCTAssertTrue(
                seen.insert(entry.id).inserted,
                "Duplicate catalog id (glyph): \(entry.glyph)"
            )
        }
    }

    func testFlagHaystackSearchableByRegionalDescriptor() {
        let usFlag = "\u{1F1FA}\u{1F1F8}"
        let entries = SumiEmojiCatalog.allEntries
        let haystack = entries.first { $0.glyph == usFlag }?.searchHaystack ?? ""
        XCTAssertFalse(haystack.isEmpty)
        let matches = SumiEmojiCatalog.entries(matching: "regional", in: entries)
        XCTAssertTrue(matches.contains { $0.glyph == usFlag })
    }

    func testMultiWordQueryFindsGrinningFaceViaTokenIndex() {
        let entries = SumiEmojiCatalog.allEntries
        let matches = SumiEmojiCatalog.entries(matching: "grinning face", in: entries)
        XCTAssertTrue(matches.contains { $0.glyph == "😀" })
    }

    func testNonISOFlagPairNotInCatalog() {
        // "QQ" is not an ISO 3166-1 alpha-2 code; avoid arbitrary regional-indicator pairs.
        let bogus = "\u{1F1F6}\u{1F1F6}"
        XCTAssertFalse(SumiEmojiCatalog.allEntries.contains { $0.glyph == bogus })
    }

    func testCatalogFewerEntriesThanFullRegionalGrid() {
        // Previously 26 * 25 arbitrary pairs plus scalars; ISO list is much smaller than 650 flags.
        let flagLike = SumiEmojiCatalog.allEntries.filter { $0.glyph.unicodeScalars.count == 2 }
        XCTAssertLessThan(flagLike.count, 400)
    }

    func testCatalogExcludesModernOnlyOutlyingOceaniaRegionCode() {
        let regionCodes = SumiEmojiCatalog.allEntries.compactMap { Self.flagRegionCode(from: $0.glyph) }
        XCTAssertFalse(regionCodes.contains("QO"))
    }

    func testCatalogFlagRegionCodesRemainAlphabeticallyOrdered() {
        let regionCodes = SumiEmojiCatalog.allEntries.compactMap { Self.flagRegionCode(from: $0.glyph) }
        XCTAssertFalse(regionCodes.isEmpty)
        XCTAssertEqual(regionCodes, regionCodes.sorted())
    }
}
