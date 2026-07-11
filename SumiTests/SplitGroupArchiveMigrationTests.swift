import Foundation
import SumiDomain
import XCTest

@testable import Sumi

final class SplitGroupArchiveMigrationTests: XCTestCase {
    func testVersion2EncoderAlwaysWritesEnvelope() throws {
        let firstID = UUID()
        let secondID = UUID()
        let group = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: [
                    .regularTab(firstID),
                    .regularTab(secondID),
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: UUID())
            )
        )

        let data = try TabPersistenceCodec().encodeSplitGroups([group])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual((object["groups"] as? [Any])?.count, 1)
        XCTAssertFalse(data.containsASCII("activeTabId"))
        XCTAssertFalse(data.containsASCII("tabId"))

        guard case .version2(
            groups: let decoded,
            discardedEntryCount: let discardedEntryCount
        ) = try TabPersistenceCodec().decodeSplitGroupArchive(from: data) else {
            return XCTFail("Expected a version 2 split archive")
        }
        XCTAssertEqual(decoded, [group])
        XCTAssertEqual(discardedEntryCount, 0)
    }

    func testDecoderRejectsUnknownEnvelopeVersionWithoutLegacyFallback() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 3,
                "groups": [],
            ]
        )

        XCTAssertThrowsError(
            try TabPersistenceCodec().decodeSplitGroupArchive(from: data)
        )
    }

    func testVersion2DecoderDropsOnlyMalformedEntryAndPreservesOrder() throws {
        let firstIDs = [UUID(), UUID()]
        let secondIDs = [UUID(), UUID()]
        let first = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: firstIDs.map(SplitMember.regularTab),
                layoutKind: .vertical
            )
        )
        let second = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: secondIDs.map(SplitMember.regularTab),
                layoutKind: .horizontal
            )
        )
        let data = try version2ArchiveData([
            encodedJSONObject(first),
            ["corrupt": true],
            encodedJSONObject(second),
        ])

        guard case .version2(
            groups: let decoded,
            discardedEntryCount: let discardedEntryCount
        ) = try TabPersistenceCodec().decodeSplitGroupArchive(from: data) else {
            return XCTFail("Expected a version 2 split archive")
        }

        XCTAssertEqual(decoded.map(\.id), [first.id, second.id])
        XCTAssertEqual(discardedEntryCount, 1)

        var reasons = Set<String>()
        let restored = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: Set(firstIDs + secondIDs),
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )
        XCTAssertEqual(restored.map(\.id), [first.id, second.id])
        XCTAssertTrue(
            reasons.contains("removed unreadable split group entry")
        )
    }

    func testVersion2DecoderRejectsMalformedEnvelopeGroupsValue() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 2,
                "groups": "not-an-array",
            ]
        )

        XCTAssertThrowsError(
            try TabPersistenceCodec().decodeSplitGroupArchive(from: data)
        )

        var reasons = Set<String>()
        let restored = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [],
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )
        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(reasons, ["removed unreadable split groups"])
    }

    func testLegacyLiveShortcutLeafMigratesToStablePinAndDiscardsGlobalActive() throws {
        let groupID = UUID()
        let firstPinID = UUID()
        let liveShortcutTabID = UUID()
        let secondPinID = UUID()
        let spaceID = UUID()
        let folderID = UUID()
        let data = try legacyArchiveData([
            legacyGroup(
                id: groupID,
                layoutTree: legacySplit([
                    legacyLeaf(firstPinID),
                    legacyLeaf(liveShortcutTabID),
                ]),
                activeTabID: liveShortcutTabID,
                host: [
                    "kind": "shortcutPinned",
                    "spaceId": spaceID.uuidString,
                    "index": 4,
                ],
                members: [
                    legacyMember(
                        tabID: liveShortcutTabID,
                        pinID: secondPinID,
                        origin: [
                            "kind": "spacePinned",
                            "spaceId": spaceID.uuidString,
                            "folderId": folderID.uuidString,
                            "index": 2,
                        ]
                    ),
                ]
            ),
        ])
        var reasons = Set<String>()

        let groups = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [],
            shortcutReturnPlacementsByPinID: [
                firstPinID: .spacePinned(
                    spaceId: spaceID,
                    folderId: folderID,
                    index: 1
                ),
                secondPinID: .spacePinned(
                    spaceId: spaceID,
                    folderId: folderID,
                    index: 2
                ),
            ],
            repairReasons: &reasons
        )

        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.id, groupID)
        XCTAssertEqual(
            group.memberIDs,
            [.shortcutPin(firstPinID), .shortcutPin(secondPinID)]
        )
        XCTAssertEqual(
            group.member(for: .shortcutPin(secondPinID))?.returnPlacement,
            .spacePinned(
                spaceId: spaceID,
                folderId: folderID,
                index: 2
            )
        )
        guard case .shortcutSidebar(
            let containerSpaceID,
            _,
            let containerFolderID,
            let index
        ) = group.container else {
            return XCTFail("Expected migrated shortcut sidebar container")
        }
        XCTAssertEqual(containerSpaceID, spaceID)
        XCTAssertEqual(containerFolderID, folderID)
        XCTAssertEqual(index, 4)
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason.migratedArchive
            )
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason.reboundLiveShortcut
            )
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason
                    .discardedGlobalActiveMember
            )
        )
    }

    func testLegacyUnknownLeafIsRemovedAndNestedLayoutCollapses() throws {
        let firstID = UUID()
        let secondID = UUID()
        let unknownID = UUID()
        let data = try legacyArchiveData([
            legacyGroup(
                layoutTree: legacySplit([
                    legacyLeaf(firstID),
                    legacySplit(
                        [
                            legacyLeaf(unknownID),
                            legacyLeaf(secondID),
                        ],
                        axis: "column",
                        size: 0.75
                    ),
                ])
            ),
        ])
        var reasons = Set<String>()

        let groups = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [firstID, secondID],
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )

        XCTAssertEqual(
            groups.first?.memberIDs,
            [.regularTab(firstID), .regularTab(secondID)]
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason.removedUnknownMember
            )
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason.collapsedLayout
            )
        )
    }

    func testStaleLegacyPinMetadataFallsBackToValidRegularLeaf() throws {
        let firstID = UUID()
        let secondID = UUID()
        let missingPinID = UUID()
        let data = try legacyArchiveData([
            legacyGroup(
                layoutTree: legacySplit([
                    legacyLeaf(firstID),
                    legacyLeaf(secondID),
                ]),
                members: [
                    legacyMember(
                        tabID: firstID,
                        pinID: missingPinID,
                        origin: [
                            "kind": "essential",
                            "index": 0,
                        ]
                    ),
                ]
            ),
        ])
        var reasons = Set<String>()

        let groups = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [firstID, secondID],
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )

        XCTAssertEqual(
            groups.first?.memberIDs,
            [.regularTab(firstID), .regularTab(secondID)]
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason
                    .ignoredStaleShortcutMetadata
            )
        )
    }

    func testLegacyShortcutOriginFallsBackToValidatedCatalogPlacement() throws {
        let regularID = UUID()
        let liveShortcutID = UUID()
        let pinID = UUID()
        let spaceID = UUID()
        let staleFolderID = UUID()
        let validFolderID = UUID()
        let data = try legacyArchiveData([
            legacyGroup(
                layoutTree: legacySplit([
                    legacyLeaf(regularID),
                    legacyLeaf(liveShortcutID),
                ]),
                members: [
                    legacyMember(
                        tabID: liveShortcutID,
                        pinID: pinID,
                        origin: [
                            "kind": "spacePinned",
                            "spaceId": spaceID.uuidString,
                            "folderId": staleFolderID.uuidString,
                            "index": 1,
                        ]
                    ),
                ]
            ),
        ])
        var reasons = Set<String>()

        let groups = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [regularID],
            shortcutReturnPlacementsByPinID: [
                pinID: .spacePinned(
                    spaceId: spaceID,
                    folderId: validFolderID,
                    index: 7
                ),
            ],
            repairReasons: &reasons
        )

        XCTAssertEqual(
            groups.first?.member(for: .shortcutPin(pinID))?
                .returnPlacement,
            .spacePinned(
                spaceId: spaceID,
                folderId: validFolderID,
                index: 7
            )
        )
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason
                    .repairedShortcutPlacement
            )
        )
    }

    func testShortcutContainerFolderRequiresOneConsistentCatalogFolder() throws {
        let firstPinID = UUID()
        let secondPinID = UUID()
        let spaceID = UUID()
        let firstFolderID = UUID()
        let secondFolderID = UUID()
        let data = try legacyArchiveData([
            legacyGroup(
                layoutTree: legacySplit([
                    legacyLeaf(firstPinID),
                    legacyLeaf(secondPinID),
                ]),
                host: [
                    "kind": "shortcutPinned",
                    "spaceId": spaceID.uuidString,
                    "index": 1,
                ]
            ),
        ])
        var reasons = Set<String>()

        let groups = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [],
            shortcutReturnPlacementsByPinID: [
                firstPinID: .spacePinned(
                    spaceId: spaceID,
                    folderId: firstFolderID,
                    index: 0
                ),
                secondPinID: .spacePinned(
                    spaceId: spaceID,
                    folderId: secondFolderID,
                    index: 1
                ),
            ],
            repairReasons: &reasons
        )

        let group = try XCTUnwrap(groups.first)
        guard case .shortcutSidebar(_, _, let folderID, _) =
            group.container else {
            return XCTFail("Expected shortcut sidebar container")
        }
        XCTAssertNil(folderID)
        XCTAssertTrue(
            reasons.contains(
                LegacySplitGroupV1RepairReason
                    .discardedAmbiguousFolder
            )
        )
    }

    func testVersion2RestorePrunesMembersMissingFromTypedCatalogs() throws {
        let firstID = UUID()
        let secondID = UUID()
        let staleID = UUID()
        let group = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: [
                    .regularTab(firstID),
                    .regularTab(staleID),
                    .regularTab(secondID),
                ],
                layoutKind: .vertical
            )
        )
        let data = try TabPersistenceCodec().encodeSplitGroups([group])
        var reasons = Set<String>()

        let restored = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: [firstID, secondID],
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )

        XCTAssertEqual(
            restored.first?.memberIDs,
            [.regularTab(firstID), .regularTab(secondID)]
        )
        XCTAssertTrue(reasons.contains("removed stale split group member"))
    }

    func testVersion2RestoreDropsDuplicateAndOverlappingEntriesInOrder() throws {
        let firstIDs = [UUID(), UUID()]
        let trailingIDs = [UUID(), UUID()]
        let overlapOnlyID = UUID()
        let firstGroupID = UUID()
        let first = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                id: firstGroupID,
                members: firstIDs.map(SplitMember.regularTab),
                layoutKind: .vertical
            )
        )
        let duplicateIdentity = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                id: firstGroupID,
                members: trailingIDs.map(SplitMember.regularTab),
                layoutKind: .horizontal
            )
        )
        let overlap = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: [
                    .regularTab(firstIDs[1]),
                    .regularTab(overlapOnlyID),
                ],
                layoutKind: .vertical
            )
        )
        let trailing = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: trailingIDs.map(SplitMember.regularTab),
                layoutKind: .horizontal
            )
        )
        let data = try version2ArchiveData([
            encodedJSONObject(first),
            encodedJSONObject(duplicateIdentity),
            encodedJSONObject(overlap),
            encodedJSONObject(trailing),
        ])
        var reasons = Set<String>()

        guard case .version2(
            groups: let decoded,
            discardedEntryCount: let discardedEntryCount
        ) = try TabPersistenceCodec().decodeSplitGroupArchive(from: data) else {
            return XCTFail("Expected a version 2 split archive")
        }
        XCTAssertEqual(
            decoded.map(\.id),
            [first.id, duplicateIdentity.id, overlap.id, trailing.id]
        )
        XCTAssertEqual(discardedEntryCount, 0)

        let restored = TabRestoreRepair.restoreSplitGroups(
            from: data,
            regularTabIDs: Set(
                firstIDs + trailingIDs + [overlapOnlyID]
            ),
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &reasons
        )

        XCTAssertEqual(restored.map(\.id), [first.id, trailing.id])
        XCTAssertTrue(reasons.contains("removed overlapping split groups"))
    }
}

private extension SplitGroupArchiveMigrationTests {
    func version2ArchiveData(_ groups: [Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 2,
                "groups": groups,
            ]
        )
    }

    func encodedJSONObject(
        _ group: SumiDomain.SplitGroup
    ) throws -> Any {
        try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)
        )
    }

    func legacyArchiveData(
        _ groups: [[String: Any]]
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: groups)
    }

    func legacyGroup(
        id: UUID = UUID(),
        layoutTree: [String: Any],
        activeTabID: UUID? = nil,
        host: [String: Any] = ["kind": "regular"],
        members: [[String: Any]] = []
    ) -> [String: Any] {
        var group: [String: Any] = [
            "id": id.uuidString,
            "layoutKind": "vertical",
            "layoutTree": layoutTree,
            "host": host,
            "members": members,
        ]
        if let activeTabID {
            group["activeTabId"] = activeTabID.uuidString
        }
        return group
    }

    func legacyLeaf(
        _ tabID: UUID,
        size: Double = 0.5
    ) -> [String: Any] {
        [
            "leaf": [
                "tabId": tabID.uuidString,
                "size": size,
            ],
        ]
    }

    func legacySplit(
        _ children: [[String: Any]],
        axis: String = "row",
        size: Double = 1
    ) -> [String: Any] {
        [
            "split": [
                "axis": axis,
                "size": size,
                "children": children,
            ],
        ]
    }

    func legacyMember(
        tabID: UUID,
        pinID: UUID?,
        origin: [String: Any]
    ) -> [String: Any] {
        var member: [String: Any] = [
            "tabId": tabID.uuidString,
            "origin": origin,
        ]
        if let pinID {
            member["pinId"] = pinID.uuidString
        }
        return member
    }
}

private extension Data {
    func containsASCII(_ value: String) -> Bool {
        range(of: Data(value.utf8)) != nil
    }
}
