import Foundation
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiSelectedFilterBundleBuilderTests: XCTestCase {
    func testInitializationRemovesAbandonedBuildTransaction() throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let abandoned = fixture.buildRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: abandoned,
            withIntermediateDirectories: true
        )

        _ = SumiSelectedFilterBundleBuilder(buildRoot: fixture.buildRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
    }

    func testBuildsOneAtomicNativeAdvancedAndURLCleaningGeneration() async throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let sourceData = Data(
            """
            ||ads.example^
            example.org##.ad
            example.org#?##card:has(.promotion)
            example.org#%#//scriptlet('log', 'matched')
            $removeparam=utm_source
            """.utf8
        )
        let builder = SumiSelectedFilterBundleBuilder(
            buildRoot: fixture.buildRoot,
            fetch: { _ in sourceData }
        )
        let list = SumiFilterListCatalog.List(
            id: "fixture-list",
            displayName: "Fixture list",
            url: URL(string: "https://example.org/filter.txt")!,
            category: .ads,
            defaultEnabled: false,
            description: "",
            languages: nil,
            trustLevel: nil
        )

        let output = try await builder.build(selectedLists: [list])
        let bundle = try SumiAdblockNativeBundleReader().load(
            from: output
        )
        let definitions = try SumiAdblockNativeBundleReader()
            .contentRuleListDefinitions(from: bundle)
        let artifactURLs = try SumiAdblockNativeBundleReader()
            .stagedAdvancedArtifactURLs(from: bundle)

        XCTAssertEqual(bundle.manifest.lists.map(\.id), ["fixture-list"])
        XCTAssertEqual(
            Set(bundle.manifest.shards.compactMap {
                $0.protectionGroupKind(
                    bundleProfileId: bundle.manifest.profileId
                )
            }),
            [.adblockAdsPrivacyNetwork]
        )
        XCTAssertEqual(definitions.count, 1)
        XCTAssertGreaterThan(bundle.manifest.advancedBlocking?.ruleCount ?? 0, 0)
        let cosmeticURL = try XCTUnwrap(
            artifactURLs[AdblockCosmeticDomainIndex.artifactRelativePath]
        )
        let cosmeticIndex = try AdblockCosmeticDomainIndex(
            data: Data(contentsOf: cosmeticURL)
        )
        XCTAssertEqual(cosmeticIndex.selectors(forHost: "example.org"), [".ad"])
        for definition in definitions {
            XCTAssertFalse(definition.encodedContentRuleList.contains(".ad"))
        }
        let cleaningURL = try XCTUnwrap(
            artifactURLs[".webext/removeparam.json"]
        )
        let cleaningRules = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: cleaningURL)
            ) as? [[String: Any]]
        )
        XCTAssertEqual(cleaningRules.count, 1)

        await builder.discard(output)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: output.deletingLastPathComponent().path
            )
        )
    }

    func testEmptySelectionProducesAnInertAdblockGeneration() async throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let builder = SumiSelectedFilterBundleBuilder(
            buildRoot: fixture.buildRoot,
            fetch: { _ in XCTFail("Empty selection must not fetch"); return Data() }
        )

        let output = try await builder.build(selectedLists: [])
        let bundle = try SumiAdblockNativeBundleReader().load(
            from: output
        )

        XCTAssertTrue(bundle.manifest.lists.isEmpty)
        XCTAssertNil(bundle.manifest.advancedBlocking)
        XCTAssertEqual(
            bundle.manifest.shards.filter {
                $0.protectionGroupKind(
                    bundleProfileId: bundle.manifest.profileId
                ) == .adblockAdsPrivacyNetwork
            }.map(\.ruleCount),
            [0]
        )
        let definitions = try SumiAdblockNativeBundleReader()
            .contentRuleListDefinitions(from: bundle)
        let inertDefinition = try XCTUnwrap(
            definitions.first { $0.name.contains("selected") }
        )
        _ = try await compile(inertDefinition)
        await builder.discard(output)
    }

    func testKeepsDomainCosmeticsInWebKitWithoutAdvancedEngine() async throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let builder = SumiSelectedFilterBundleBuilder(
            buildRoot: fixture.buildRoot,
            fetch: { _ in Data("example.org##.domain-ad\n".utf8) }
        )
        let list = SumiFilterListCatalog.List(
            id: "cosmetic-only",
            displayName: "Cosmetic only",
            url: URL(string: "https://example.org/filter.txt")!,
            category: .ads,
            defaultEnabled: false,
            description: "",
            languages: nil,
            trustLevel: nil
        )

        let output = try await builder.build(selectedLists: [list])
        let bundle = try SumiAdblockNativeBundleReader().load(from: output)
        XCTAssertNil(bundle.manifest.advancedBlocking)
        let definitions = try SumiAdblockNativeBundleReader()
            .contentRuleListDefinitions(from: bundle)
        XCTAssertTrue(
            definitions.contains { $0.encodedContentRuleList.contains(".domain-ad") }
        )
        for definition in definitions {
            _ = try await compile(definition)
        }
        await builder.discard(output)
    }

    func testAdvancedGenerationWritesEmptyCosmeticMigrationMarker() async throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let builder = SumiSelectedFilterBundleBuilder(
            buildRoot: fixture.buildRoot,
            fetch: { _ in Data("example.org#?##card:has(.promotion)\n".utf8) }
        )
        let list = SumiFilterListCatalog.List(
            id: "advanced-only",
            displayName: "Advanced only",
            url: URL(string: "https://example.org/filter.txt")!,
            category: .ads,
            defaultEnabled: false,
            description: "",
            languages: nil,
            trustLevel: nil
        )

        let output = try await builder.build(selectedLists: [list])
        let bundle = try SumiAdblockNativeBundleReader().load(from: output)
        let artifact = try XCTUnwrap(
            bundle.manifest.advancedBlocking?.artifacts.first {
                $0.role == .domainCosmeticRules
            }
        )
        let index = try AdblockCosmeticDomainIndex(
            data: Data(contentsOf: output.appendingPathComponent(
                artifact.relativePath
            ))
        )
        XCTAssertTrue(index.isEmpty)
        await builder.discard(output)
    }

    func testPreservesConverterOrderingForCosmeticExceptions() async throws {
        let fixture = try SelectedBundleFixture()
        defer { fixture.remove() }
        let cosmeticURL = URL(string: "https://example.org/cosmetic.txt")!
        let exceptionURL = URL(string: "https://example.org/exceptions.txt")!
        let builder = SumiSelectedFilterBundleBuilder(
            buildRoot: fixture.buildRoot,
            fetch: { url in
                if url == cosmeticURL {
                    return Data(
                        "##.generic-ad\n||ads.example^\n".utf8
                    )
                }
                return Data(
                    "##.second-generic-ad\n"
                        .appending("@@||browserbench.org^$generichide\n")
                        .appending("browserbench.org##.specific-ad\n")
                        .appending("||tracker.example^\n")
                        .appending(
                            "@@||ads.example^$domain=browserbench.org\n"
                        ).utf8
                )
            }
        )
        let lists = [
            SumiFilterListCatalog.List(
                id: "cosmetic",
                displayName: "Cosmetic",
                url: cosmeticURL,
                category: .ads,
                defaultEnabled: false,
                description: "",
                languages: nil,
                trustLevel: nil
            ),
            SumiFilterListCatalog.List(
                id: "exceptions",
                displayName: "Exceptions",
                url: exceptionURL,
                category: .ads,
                defaultEnabled: false,
                description: "",
                languages: nil,
                trustLevel: nil
            ),
        ]

        let output = try await builder.build(selectedLists: lists)
        let bundle = try SumiAdblockNativeBundleReader().load(
            from: output
        )
        let definition = try XCTUnwrap(
            try SumiAdblockNativeBundleReader()
                .contentRuleListDefinitions(from: bundle).first
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(definition.encodedContentRuleList.utf8)
            ) as? [[String: Any]]
        )
        let actionTypes = try rules.map { rule in
            try XCTUnwrap(
                (rule["action"] as? [String: Any])?["type"] as? String
            )
        }
        let firstBlock = try XCTUnwrap(
            actionTypes.firstIndex(of: "block")
        )
        let lastBlock = try XCTUnwrap(
            actionTypes.lastIndex(of: "block")
        )
        let browserbenchException = try XCTUnwrap(
            rules.firstIndex { rule in
                let trigger = rule["trigger"] as? [String: Any]
                return (trigger?["if-domain"] as? [String])?
                    .contains("*browserbench.org") == true
                    && (rule["action"] as? [String: Any])?["type"]
                        as? String == "ignore-previous-rules"
            }
        )
        let artifact = try XCTUnwrap(
            bundle.manifest.advancedBlocking?.artifacts.first {
                $0.role == .domainCosmeticRules
            }
        )
        let index = try AdblockCosmeticDomainIndex(
            data: Data(contentsOf: bundle.directoryURL.appendingPathComponent(
                artifact.relativePath
            ))
        )
        let networkException = try XCTUnwrap(
            rules.lastIndex { rule in
                (rule["action"] as? [String: Any])?["type"] as? String
                    == "ignore-previous-rules"
            }
        )

        XCTAssertEqual(bundle.manifest.shards.count, 2)
        XCTAssertFalse(rules.contains { rule in
            (rule["action"] as? [String: Any])?["selector"]
                as? String == ".specific-ad"
        })
        XCTAssertEqual(index.selectors(forHost: "browserbench.org"), [
            ".specific-ad",
        ])
        XCTAssertGreaterThan(browserbenchException, 0)
        XCTAssertLessThan(browserbenchException, firstBlock)
        XCTAssertGreaterThan(networkException, lastBlock)
        await builder.discard(output)
    }

    private func compile(
        _ definition: SumiContentRuleListDefinition
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "SumiSelectedFilterBundleBuilderTests-\(UUID().uuidString)",
                encodedContentRuleList: definition.encodedContentRuleList
            ) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(
                        throwing: error ?? CocoaError(.coderInvalidValue)
                    )
                }
            }
        }
    }
}

private struct SelectedBundleFixture {
    let root: URL
    let buildRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiSelectedFilterBundleBuilderTests-\(UUID().uuidString)",
            isDirectory: true
        )
        buildRoot = root.appendingPathComponent("Build", isDirectory: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
