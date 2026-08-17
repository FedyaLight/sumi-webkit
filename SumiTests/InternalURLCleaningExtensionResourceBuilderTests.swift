import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class InternalURLCleaningExtensionResourceBuilderTests: XCTestCase {
    func testBuildsLoadableStaticDNRPackageWithSiteExceptions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceRules: [[String: Any]] = [
            [
                "id": 7,
                "priority": 1,
                "action": [
                    "type": "redirect",
                    "redirect": [
                        "transform": [
                            "queryTransform": [
                                "removeParams": ["utm_source"],
                            ],
                        ],
                    ],
                ],
                "condition": [
                    "resourceTypes": ["main_frame", "sub_frame"],
                    "urlFilter": "^utm_source=",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: sourceRules).write(
            to: fixture.rulesURL,
            options: .atomic
        )
        let builder = InternalURLCleaningExtensionResourceBuilder(
            rootDirectory: fixture.outputRoot
        )

        let package = try await builder.resources(
            for: SumiURLCleaningContribution(
                generationID: "generation-a",
                rulesURL: fixture.rulesURL,
                disabledDomains: ["example.com"]
            ),
            profileID: fixture.profileID,
            fingerprint: "fingerprint-a"
        )

        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: package.appendingPathComponent("rules.json"))
            ) as? [[String: Any]]
        )
        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(
            rules.map { $0["id"] as? Int },
            [1_500_000, 1_500_001, 1_500_002]
        )
        XCTAssertEqual(rules[0]["priority"] as? Int, 20_000)
        XCTAssertEqual(rules[1]["priority"] as? Int, 20_000)
        XCTAssertEqual(
            ((rules[0]["condition"] as? [String: Any])?["requestDomains"] as? [String]),
            ["example.com"]
        )
        XCTAssertEqual(
            ((rules[1]["condition"] as? [String: Any])?["initiatorDomains"] as? [String]),
            ["example.com"]
        )
        XCTAssertEqual(rules[2]["priority"] as? Int, 1)

        let extensionPackage = try await WKWebExtension(resourceBaseURL: package)
        XCTAssertTrue(
            extensionPackage.errors.isEmpty,
            "\(extensionPackage.errors.map { ($0 as NSError).userInfo })"
        )
        XCTAssertTrue(
            extensionPackage.requestedPermissions.contains(
                WKWebExtension.Permission("declarativeNetRequest")
            )
        )
    }

    func testReusesContentAddressedPackageWithoutRewritingIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("[]".utf8).write(to: fixture.rulesURL, options: .atomic)
        let builder = InternalURLCleaningExtensionResourceBuilder(
            rootDirectory: fixture.outputRoot
        )
        let contribution = SumiURLCleaningContribution(
            generationID: "generation-a",
            rulesURL: fixture.rulesURL,
            disabledDomains: []
        )

        let first = try await builder.resources(
            for: contribution,
            profileID: fixture.profileID,
            fingerprint: "stable"
        )
        let rulesURL = first.appendingPathComponent("rules.json")
        let firstModificationDate = try XCTUnwrap(
            try rulesURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        let second = try await builder.resources(
            for: contribution,
            profileID: fixture.profileID,
            fingerprint: "stable"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try rulesURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
            firstModificationDate
        )
    }

    func testContributionLoadsIntoProvisionedSharedControllerAndUnloadsCleanly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("[]".utf8).write(to: fixture.rulesURL, options: .atomic)
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let provisioning = StubControllerProvisioning(controller: controller)
        let owner = InternalWebExtensionContributionOwner(
            controllerProvisioning: provisioning,
            resourceBuilder: InternalURLCleaningExtensionResourceBuilder(
                rootDirectory: fixture.outputRoot
            )
        )

        owner.reconcile(
            SumiURLCleaningContribution(
                generationID: "generation-a",
                rulesURL: fixture.rulesURL,
                disabledDomains: []
            ),
            profileID: fixture.profileID
        )
        await owner.drainTasksForTests()

        let context = try XCTUnwrap(
            owner.loadedContextForTests(profileID: fixture.profileID)
        )
        XCTAssertIdentical(context.webExtensionController, controller)
        XCTAssertEqual(provisioning.requestedProfileIDs, [fixture.profileID])

        owner.reconcile(
            SumiURLCleaningContribution(
                generationID: "generation-a",
                rulesURL: fixture.rulesURL,
                disabledDomains: ["example.com"]
            ),
            profileID: fixture.profileID
        )
        XCTAssertNil(context.webExtensionController)
        await owner.drainTasksForTests()
        let replacement = try XCTUnwrap(
            owner.loadedContextForTests(profileID: fixture.profileID)
        )
        XCTAssertNotIdentical(replacement, context)
        XCTAssertIdentical(replacement.webExtensionController, controller)

        owner.reconcile(nil, profileID: fixture.profileID)
        XCTAssertNil(replacement.webExtensionController)
        XCTAssertNil(owner.loadedContextForTests(profileID: fixture.profileID))
    }
}

@MainActor
private final class StubControllerProvisioning: ExtensionControllerProvisioning {
    let controller: WKWebExtensionController
    private(set) var requestedProfileIDs: [UUID] = []

    init(controller: WKWebExtensionController) {
        self.controller = controller
    }

    func controllerIfAdmitted(
        for profileID: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController? {
        requestedProfileIDs.append(profileID)
        return controller
    }
}

private struct Fixture {
    let root: URL
    let outputRoot: URL
    let rulesURL: URL
    let profileID = UUID()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiURLCleaning-\(UUID().uuidString)",
            isDirectory: true
        )
        outputRoot = root.appendingPathComponent("packages", isDirectory: true)
        rulesURL = root.appendingPathComponent("source-rules.json")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
