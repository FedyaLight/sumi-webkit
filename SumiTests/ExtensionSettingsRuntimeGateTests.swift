import SwiftUI
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionSettingsRuntimeGateTests: XCTestCase {
    func testUnavailablePartialRuntimeDoesNotConstructScanSession() {
        let defaults = TestDefaultsHarness()
        defer { defaults.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: defaults.defaults
            )
        )
        registry.enable(.extensions)
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            browserConfiguration: BrowserConfiguration()
        )
        let readiness = ExtensionSettingsRuntimeReadiness(
            extensionsModule: module
        )
        let probe = ExtensionSettingsRuntimeGateProbe()
        let gate = ExtensionSettingsRuntimeGate(readiness: readiness) {
            probe.makeSessionBackedContent()
        }

        _ = gate.body

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(readiness, .unavailable)
        XCTAssertNil(module.managerForTesting())
        XCTAssertEqual(probe.sessionConstructionCount, 0)
        XCTAssertEqual(probe.scanCallCount, 0)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ExtensionSettingsRuntimeGateProbe {
    var sessionConstructionCount = 0
    private(set) var scanCallCount = 0

    func makeSessionBackedContent() -> EmptyView {
        sessionConstructionCount += 1
        _ = ExtensionSettingsScanSession(
            scan: {
                await self.recordScan()
                return .init(candidates: [], issues: [])
            },
            loadContentBlockers: { [] }
        )
        return EmptyView()
    }

    func recordScan() {
        scanCallCount += 1
    }
}
