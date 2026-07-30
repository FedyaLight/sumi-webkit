@testable import Sumi
import Foundation
import Observation
import SwiftUI
import XCTest
import SumiDomain

@MainActor
final class GeneralSettingsBoundaryTests: XCTestCase {
    func testUpsertAppendsNewEngine() {
        let engines = [makeEngine(id: "a")]
        let added = makeEngine(id: "b")

        let updated = GeneralSearchEngineMutation.upserting(added, in: engines)

        XCTAssertEqual(updated.map(\.id), ["a", "b"])
    }

    func testUpsertReplacesExistingEngineWithoutChangingOrder() {
        let engines = [makeEngine(id: "a"), makeEngine(id: "b")]
        let edited = makeEngine(id: "a", name: "Edited")

        let updated = GeneralSearchEngineMutation.upserting(edited, in: engines)

        XCTAssertEqual(updated.map(\.id), ["a", "b"])
        XCTAssertEqual(updated.first?.name, "Edited")
    }

    func testTabSearchMutationChangesOnlyRequestedEngine() {
        let engines = [
            makeEngine(id: "a", tabSearchEnabled: false),
            makeEngine(id: "b", tabSearchEnabled: false),
        ]

        let updated = GeneralSearchEngineMutation.settingTabSearch(
            true,
            for: "b",
            in: engines
        )

        XCTAssertEqual(updated.map(\.tabSearchEnabled), [false, true])
    }

    func testRemovalPreservesAtLeastOneEngineInvariant() {
        let onlyEngine = [makeEngine(id: "a")]

        XCTAssertNil(
            GeneralSearchEngineMutation.removing(engineID: "a", from: onlyEngine)
        )
        XCTAssertNil(
            GeneralSearchEngineMutation.removing(
                engineID: "missing",
                from: [makeEngine(id: "a"), makeEngine(id: "b")]
            )
        )
    }

    func testRemovalDeletesExistingEngineWhenAnotherRemains() throws {
        let engines = [makeEngine(id: "a"), makeEngine(id: "b")]

        let updated = try XCTUnwrap(
            GeneralSearchEngineMutation.removing(engineID: "a", from: engines)
        )

        XCTAssertEqual(updated.map(\.id), ["b"])
    }

    func testReorderMovesByStableIdentity() {
        let engines = [
            makeEngine(id: "a"),
            makeEngine(id: "b"),
            makeEngine(id: "c"),
        ]

        let movedForward = GeneralSearchEngineMutation.moving(
            ReorderMove(id: "a", targetIndex: 2),
            in: engines
        )
        let movedBackward = GeneralSearchEngineMutation.moving(
            ReorderMove(id: "c", targetIndex: 0),
            in: engines
        )

        XCTAssertEqual(movedForward.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(movedBackward.map(\.id), ["c", "a", "b"])
    }

    func testReorderClampsTargetAndIgnoresUnknownIdentity() {
        let engines = [makeEngine(id: "a"), makeEngine(id: "b")]

        XCTAssertEqual(
            GeneralSearchEngineMutation.moving(
                ReorderMove(id: "a", targetIndex: 99),
                in: engines
            ).map(\.id),
            ["b", "a"]
        )
        XCTAssertEqual(
            GeneralSearchEngineMutation.moving(
                ReorderMove(id: "missing", targetIndex: 0),
                in: engines
            ),
            engines
        )
    }

    func testEditorValidationRejectsMissingNameAndQueryToken() {
        var input = makeEditorInput(name: "", template: "https://example.com/?q={query}")
        XCTAssertEqual(input.validationMessage, "Name is required.")

        input = makeEditorInput(name: "Example", template: "https://example.com/search")
        XCTAssertEqual(
            input.validationMessage,
            "Search URL must contain {query} where the query should go."
        )
    }

    func testEditorValidationRejectsTemplateWithoutHTTPHost() {
        let input = makeEditorInput(
            name: "Example",
            template: "https:///?q={query}"
        )

        XCTAssertEqual(
            input.validationMessage,
            "Enter a valid http or https search URL."
        )
        XCTAssertNil(input.engine(id: "example"))
    }

    func testEditorValidationNormalizesTemplateAndDerivesDomain() throws {
        let input = makeEditorInput(
            name: "  Example  ",
            domain: "",
            template: "example.com/search?q=%@"
        )

        let engine = try XCTUnwrap(input.engine(id: "example"))

        XCTAssertNil(input.validationMessage)
        XCTAssertEqual(engine.name, "Example")
        XCTAssertEqual(engine.domain, "example.com")
        XCTAssertEqual(engine.searchURLTemplate, "example.com/search?q={query}")
        XCTAssertEqual(
            input.previewURLString,
            "https://example.com/search?q=sumi+browser"
        )
    }

    func testNewTabURLValidationSeamAcceptsDomainsAndRejectsSearchText() {
        XCTAssertNil(SumiNewTabPageURL.validationMessage(for: "example.com"))
        XCTAssertEqual(
            SumiNewTabPageURL.normalizedURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertNotNil(SumiNewTabPageURL.validationMessage(for: "plain search text"))
        XCTAssertNotNil(SumiNewTabPageURL.validationMessage(for: ""))
    }

    func testSearchStoreRepairsDefaultAfterSelectedEngineRemoval() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let first = makeEngine(id: "first")
        let second = makeEngine(id: "second")
        settings.search.searchEngines = [first, second]
        settings.search.searchEngineId = first.id

        settings.search.searchEngines = try XCTUnwrap(
            GeneralSearchEngineMutation.removing(
                engineID: first.id,
                from: settings.search.searchEngines
            )
        )

        XCTAssertEqual(settings.search.searchEngineId, second.id)
    }

    func testSettingsInitializationRemovesRetiredPaletteEmptyStatePreference() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let retiredKey = "settings.commandPalette.emptyStateMode"
        harness.defaults.set("compact", forKey: retiredKey)

        _ = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertNil(harness.defaults.object(forKey: retiredKey))
    }

    func testSearchStoreRepairsCustomDefaultWhenRestoringDefaults() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let custom = makeEngine(id: "custom")
        settings.search.searchEngines = [custom]
        settings.search.searchEngineId = custom.id

        settings.search.searchEngines = SumiSearchEngine.defaultEngines()

        XCTAssertEqual(
            settings.search.searchEngineId,
            SumiSearchEngine.defaultSearchEngineID(in: settings.search.searchEngines)
        )
    }

    func testSectionConstructionNeedsOnlyExactBindingsAndProjections() {
        let engine = makeEngine(id: "example")
        let sections: [Any] = [
            GeneralWindowSettingsSection(
                askBeforeQuit: .constant(true),
                glanceEnabled: .constant(true)
            ),
            GeneralNewTabsSettingsSection(
                mode: .constant(.commandPalette),
                pageURLString: .constant("example.com")
            ),
            GeneralSearchSettingsSection(
                defaultEngineID: .constant(engine.id),
                engineChoices: [GeneralSearchEngineChoice(engine)]
            ),
            GeneralSearchEnginesSettingsSection(
                searchEngines: .constant([engine])
            ),
        ]

        let storedInputTypes = sections.flatMap { section in
            Mirror(reflecting: section).children.map { String(reflecting: type(of: $0.value)) }
        }
        XCTAssertFalse(storedInputTypes.contains { $0.contains("SumiSettingsService") })
        XCTAssertFalse(storedInputTypes.contains { $0.contains("BrowserManager") })
    }

    func testUnrelatedStoreMutationDoesNotInvalidateObservedWindowSetting() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let observation = GeneralSettingsObservationFlag()

        withObservationTracking {
            _ = settings.chrome.askBeforeQuit
            _ = settings.chrome.glanceEnabled
        } onChange: {
            observation.markChanged()
        }

        settings.search.searchEngineId = settings.search.searchEngines.last!.id
        settings.theme.themeUseSystemColors.toggle()
        XCTAssertFalse(observation.didChange)

        settings.chrome.glanceEnabled.toggle()
        XCTAssertTrue(observation.didChange)
    }

    private func makeEngine(
        id: String,
        name: String = "Engine",
        tabSearchEnabled: Bool = false
    ) -> SumiSearchEngine {
        SumiSearchEngine(
            id: id,
            name: name,
            domain: "example.com",
            searchURLTemplate: "https://example.com/?q={query}",
            tabSearchEnabled: tabSearchEnabled
        )
    }

    private func makeEditorInput(
        name: String,
        domain: String = "example.com",
        template: String
    ) -> SearchEngineEditorInput {
        SearchEngineEditorInput(
            engineID: nil,
            name: name,
            domain: domain,
            searchURLTemplate: template,
            colorHex: "#123456",
            tabSearchEnabled: true
        )
    }
}

private final class GeneralSettingsObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    var didChange: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changed
    }

    func markChanged() {
        lock.lock()
        changed = true
        lock.unlock()
    }
}
