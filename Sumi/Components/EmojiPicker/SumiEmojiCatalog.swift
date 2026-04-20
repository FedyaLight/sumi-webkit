//
//  SumiEmojiCatalog.swift
//  Sumi
//

import Foundation

/// Builds the emoji grid for the in-app picker and precomputes searchable metadata.
///
/// Picker contents are chosen for “reasonable space/launcher icons”, not identical to
/// `SumiPersistentGlyph.presentsAsEmoji` (which also accepts some pictographs for
/// persisted values). Keep both in mind when changing either side.
enum SumiEmojiCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        let glyph: String
        /// Lowercased Unicode names joined by spaces (for English keyword search).
        let searchHaystack: String
        /// Whitespace-delimited tokens from ``searchHaystack`` (whole-word AND via inverted index).
        let searchTokens: Set<String>

        var id: String { glyph }
    }

    private enum Storage {
        static let entries: [Entry] = build()
        /// Maps each whole-word token to catalog indices that contain it in ``Entry/searchTokens``.
        static let tokenInvertedIndex: [String: Set<Int>] = buildTokenInvertedIndex(entries: entries)
    }

    /// Lazily-built, immutable catalog shared by all picker instances.
    static let allEntries: [Entry] = Storage.entries

    static func entries(matching query: String, in entries: [Entry]) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return entries }

        let queryTokens = trimmed.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !queryTokens.isEmpty else { return entries }

        if queryTokens.count == 1 {
            let needle = queryTokens[0]
            return entries.filter { entry in
                entry.searchHaystack.count >= needle.count && entry.searchHaystack.contains(needle)
            }
        }

        if let indices = indicesMatchingAllTokens(queryTokens), !indices.isEmpty {
            return indices.sorted().map { entries[$0] }
        }

        return entries.filter { entry in
            queryTokens.allSatisfy { token in
                entry.searchHaystack.count >= token.count && entry.searchHaystack.contains(token)
            }
        }
    }

    /// Indices whose ``Entry/searchTokens`` contain every query token (whole-word AND).
    private static func indicesMatchingAllTokens(_ queryTokens: [String]) -> Set<Int>? {
        var candidate: Set<Int>?
        for token in queryTokens {
            let hits = Storage.tokenInvertedIndex[token] ?? []
            if hits.isEmpty { return nil }
            if candidate == nil {
                candidate = hits
            } else {
                candidate = candidate!.intersection(hits)
            }
            if candidate!.isEmpty { return nil }
        }
        return candidate
    }

    static func searchHaystack(for glyph: String) -> String {
        glyph.unicodeScalars
            .map { scalar in
                scalar.properties.name.map { $0.lowercased() } ?? ""
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func searchTokens(from haystack: String) -> Set<String> {
        let parts = haystack.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        return Set(parts)
    }

    private static func buildTokenInvertedIndex(entries: [Entry]) -> [String: Set<Int>] {
        var map: [String: Set<Int>] = [:]
        map.reserveCapacity(8_000)
        for (index, entry) in entries.enumerated() {
            for token in entry.searchTokens {
                map[token, default: []].insert(index)
            }
        }
        return map
    }

    private static func isPickableEmojiScalar(_ scalar: UnicodeScalar) -> Bool {
        let props = scalar.properties
        guard props.isEmoji else { return false }
        let v = scalar.value
        if (0x1F1E6...0x1F1FF).contains(v) { return false }
        if v == 0xFE0F || v == 0x200D { return false }
        if props.isEmojiModifier { return false }
        if props.generalCategory == .unassigned { return false }
        return true
    }

    private static func flagGlyph(fromAlpha2 upper: String) -> String? {
        guard upper.count == 2 else { return nil }
        let chars = Array(upper)
        func regionalIndicator(for letter: Character) -> UnicodeScalar? {
            guard let ascii = letter.asciiValue, (65...90).contains(ascii) else { return nil }
            let offset = UInt32(ascii - 65)
            return UnicodeScalar(0x1F1E6 + offset)
        }
        guard let a = regionalIndicator(for: chars[0]),
            let b = regionalIndicator(for: chars[1])
        else { return nil }
        return String(String.UnicodeScalarView([a, b]))
    }

    /// ISO 3166-1 alpha-2 regions from the system locale database (no arbitrary RI pairs).
    private static func appendISORegionFlagGlyphs(seen: inout Set<String>, orderedGlyphs: inout [String]) {
        let codes = Locale.isoRegionCodes.filter { code in
            guard code.count == 2 else { return false }
            return code.unicodeScalars.allSatisfy { scalar in
                let v = scalar.value
                return (65...90).contains(v) || (97...122).contains(v)
            }
        }
        for code in codes {
            let glyph = flagGlyph(fromAlpha2: code.uppercased())
            guard let glyph else { continue }
            guard seen.insert(glyph).inserted else { continue }
            orderedGlyphs.append(glyph)
        }
    }

    private static func build() -> [Entry] {
        var orderedGlyphs: [String] = []
        var seen = Set<String>()
        orderedGlyphs.reserveCapacity(2_200)

        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F,
            0x1F300...0x1F5FF,
            0x1F680...0x1F6FF,
            0x1F900...0x1F9FF,
            0x2600...0x26FF,
            0x2700...0x27BF,
        ]

        for range in ranges {
            for value in range {
                guard let scalar = UnicodeScalar(value) else { continue }
                guard isPickableEmojiScalar(scalar) else { continue }
                let glyph = String(scalar)
                guard seen.insert(glyph).inserted else { continue }
                orderedGlyphs.append(glyph)
            }
        }

        appendISORegionFlagGlyphs(seen: &seen, orderedGlyphs: &orderedGlyphs)

        var built: [Entry] = []
        built.reserveCapacity(orderedGlyphs.count)
        for glyph in orderedGlyphs {
            let haystack = searchHaystack(for: glyph)
            built.append(
                Entry(
                    glyph: glyph,
                    searchHaystack: haystack,
                    searchTokens: searchTokens(from: haystack)
                )
            )
        }
        return built
    }
}
