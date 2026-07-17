import Foundation
import SumiDomain
import XCTest

final class WorkspaceThemeCodingTests: XCTestCase {
    func testCurrentFixtureRoundTripsCanonicalWireValues() throws {
        let theme = try JSONDecoder().decode(
            WorkspaceTheme.self,
            from: Self.currentFixture
        )

        XCTAssertEqual(theme.gradientTheme.type, "gradient")
        XCTAssertEqual(theme.gradientTheme.opacity, 0.74)
        XCTAssertEqual(theme.gradientTheme.texture, 0.1875)
        XCTAssertTrue(theme.usesExplicitColorScheme)

        let color = try XCTUnwrap(theme.gradientTheme.colors.first)
        XCTAssertEqual(color.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(color.hex, "#445566")
        XCTAssertEqual(color.algorithm.rawValue, "floating")
        XCTAssertEqual(color.type.rawValue, "explicit-lightness")
        XCTAssertEqual(color.position, .monochrome)

        let encoded = try JSONEncoder().encode(theme)
        XCTAssertEqual(
            try canonicalJSON(encoded),
            try canonicalJSON(Self.currentFixture)
        )
        XCTAssertTrue(Set([theme]).contains(theme))
        requireSendable(WorkspaceTheme.self)
    }

    func testReconstructedMissingExplicitSchemeFixturePreservesStoredValues() throws {
        let theme = try JSONDecoder().decode(
            WorkspaceTheme.self,
            from: Self.missingExplicitSchemeFixture
        )

        XCTAssertTrue(theme.usesExplicitColorScheme)
        let color = try XCTUnwrap(theme.gradientTheme.colors.first)
        XCTAssertEqual(color.hex, "f4efdf")
        XCTAssertFalse(color.isPrimary)
        XCTAssertEqual(color.lightness, 1.25)
        XCTAssertEqual(color.position.x, 1.25)
        XCTAssertEqual(theme.gradientTheme.opacity, 1.2)
        XCTAssertEqual(theme.gradientTheme.texture, -0.25)

        let encoded = try JSONEncoder().encode(theme)
        let decodedAgain = try JSONDecoder().decode(WorkspaceTheme.self, from: encoded)
        XCTAssertEqual(decodedAgain, theme)
    }

    func testNestedSchemaKeysAndEnumRawValuesRemainRequired() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                WorkspaceTheme.self,
                from: Self.missingColorLightnessFixture
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                WorkspaceTheme.self,
                from: Self.unknownAlgorithmFixture
            )
        )
    }

    private func requireSendable<T: Sendable>(_: T.Type) {}

    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // These checked bytes are reconstructed from the established wire keys and
    // migration predicates. They are not asserted to be captured user payloads.
    private static let currentFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"floating","hex":"#445566","id":"00000000-0000-0000-0000-000000000001","isCustom":false,"isPrimary":true,"lightness":0.35,"position":{"x":0.66,"y":0.5},"type":"explicit-lightness"}],"opacity":0.74,"texture":0.1875,"type":"gradient"},"usesExplicitColorScheme":true}"##.utf8
    )

    private static let missingExplicitSchemeFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"floating","hex":"f4efdf","id":"00000000-0000-0000-0000-000000000002","isCustom":false,"isPrimary":false,"lightness":1.25,"position":{"x":1.25,"y":-0.5},"type":"explicit-lightness"}],"opacity":1.2,"texture":-0.25,"type":"gradient"}}"##.utf8
    )

    private static let legacyDefaultFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"triadic","hex":"#f4efdf","id":"00000000-0000-0000-0000-000000000003","isCustom":true,"isPrimary":false,"lightness":0.1,"position":{"x":0.66,"y":0.5},"type":"explicit-black-white"}],"opacity":0.62,"texture":0.0625,"type":"legacy"},"usesExplicitColorScheme":false}"##.utf8
    )

    private static let explicitFalseCustomFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"floating","hex":"#112233","id":"00000000-0000-0000-0000-000000000004","isCustom":false,"isPrimary":true,"lightness":0.2,"position":{"x":0.66,"y":0.5},"type":"explicit-lightness"}],"opacity":0.5,"texture":0.125,"type":"gradient"},"usesExplicitColorScheme":false}"##.utf8
    )

    private static let missingColorLightnessFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"floating","hex":"#445566","id":"00000000-0000-0000-0000-000000000005","isCustom":false,"isPrimary":true,"position":{"x":0.66,"y":0.5},"type":"explicit-lightness"}],"opacity":0.74,"texture":0.1875,"type":"gradient"},"usesExplicitColorScheme":true}"##.utf8
    )

    private static let unknownAlgorithmFixture = Data(
        ##"{"gradientTheme":{"colors":[{"algorithm":"future","hex":"#445566","id":"00000000-0000-0000-0000-000000000006","isCustom":false,"isPrimary":true,"lightness":0.35,"position":{"x":0.66,"y":0.5},"type":"explicit-lightness"}],"opacity":0.74,"texture":0.1875,"type":"gradient"},"usesExplicitColorScheme":true}"##.utf8
    )
}
