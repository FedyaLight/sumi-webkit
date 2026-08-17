import Foundation
import XCTest

@testable import Sumi

final class SumiRemoveParamRuleBuilderTests: XCTestCase {
    func testBuildsSupportedRuleShapesAndRejectsUnsafeScopes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiRemoveParamRuleBuilderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let source = root.appendingPathComponent("source.txt")
        try Data(
            """
            $removeparam=utm_source
            ||example.com^$removeparam=fbclid
            @@||example.com^$removeparam=fbclid
            ||example.org^$removeparam
            ||encoded.example^$removeparam=%24param,script,domain=foo.example|~bar.example
            ||bad.example^$removeparam=/^utm_/
            ||wildcard.example^$removeparam=utm,domain=*.example
            """.utf8
        ).write(to: source)
        let destination = root.appendingPathComponent("removeparam.json")

        _ = try SumiRemoveParamRuleBuilder.writeRules(
            from: [source],
            to: destination
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: destination)
            ) as? [[String: Any]]
        )

        XCTAssertEqual(rules.count, 5)
        XCTAssertEqual(
            condition(rules[0])["urlFilter"] as? String,
            "^utm_source="
        )
        XCTAssertEqual(
            condition(rules[1])["urlFilter"] as? String,
            "||example.com^*^fbclid="
        )
        XCTAssertEqual(action(rules[2])["type"] as? String, "allow")
        XCTAssertEqual(rules[2]["priority"] as? Int, 10_000)
        XCTAssertEqual(
            transform(rules[3])["query"] as? String,
            ""
        )
        XCTAssertEqual(
            queryTransform(rules[4])["removeParams"] as? [String],
            ["$param"]
        )
        XCTAssertEqual(
            condition(rules[4])["resourceTypes"] as? [String],
            ["script"]
        )
        XCTAssertEqual(
            condition(rules[4])["initiatorDomains"] as? [String],
            ["foo.example"]
        )
        XCTAssertEqual(
            condition(rules[4])["excludedInitiatorDomains"] as? [String],
            ["bar.example"]
        )
    }

    private func condition(_ rule: [String: Any]) -> [String: Any] {
        rule["condition"] as? [String: Any] ?? [:]
    }

    private func action(_ rule: [String: Any]) -> [String: Any] {
        rule["action"] as? [String: Any] ?? [:]
    }

    private func transform(_ rule: [String: Any]) -> [String: Any] {
        let redirect = action(rule)["redirect"] as? [String: Any]
        return redirect?["transform"] as? [String: Any] ?? [:]
    }

    private func queryTransform(_ rule: [String: Any]) -> [String: Any] {
        transform(rule)["queryTransform"] as? [String: Any] ?? [:]
    }
}
