import SumiDomain
import XCTest

@testable import Sumi

final class SplitLayoutInvariantTests: XCTestCase {
    func testNormalizedWeightsPreserveCardinalityAtNumericExtremes() {
        let weights = SplitLayoutSizing.normalizedWeights([
            .greatestFiniteMagnitude,
            .leastNonzeroMagnitude,
            .infinity,
            -.greatestFiniteMagnitude,
        ])

        XCTAssertEqual(weights.count, 4)
        XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.000_000_1)
        XCTAssertTrue(weights.allSatisfy { $0.isFinite && $0 > 0 })
        XCTAssertGreaterThan(weights[0], weights[1])
        XCTAssertEqual(weights[1], weights[2], accuracy: 0.000_000_1)
        XCTAssertEqual(weights[2], weights[3], accuracy: 0.000_000_1)

        let ordinaryRatio = SplitLayoutSizing.normalizedWeights([80, 20])
        XCTAssertEqual(ordinaryRatio[0], 0.8, accuracy: 0.000_000_1)
        XCTAssertEqual(ordinaryRatio[1], 0.2, accuracy: 0.000_000_1)
        XCTAssertEqual(SplitLayoutSizing.normalizedWeights([]), [])
    }

    func testRatioNormalizationProducesFinitePositiveUnitSums() throws {
        let members = makeMembers(4)
        let raw = SplitLayoutTree.split(
            axis: .row,
            weight: 1,
            children: [
                .leaf(member: members[0], weight: .nan),
                .split(
                    axis: .column,
                    weight: .greatestFiniteMagnitude,
                    children: [
                        .leaf(member: members[1], weight: -100),
                        .leaf(
                            member: members[2],
                            weight: .greatestFiniteMagnitude
                        ),
                    ]
                ),
                .leaf(member: members[3], weight: .infinity),
            ]
        )

        let normalized = SplitLayoutSizing.normalizingSiblingWeights(in: raw)
        let canonical = SplitLayoutReconciler.canonicalizedForTiles(raw)

        XCTAssertEqual(normalized.memberIDs, members.map(\.memberID))
        assertNormalizedWeights(
            in: normalized,
            context: "non-finite and non-positive input"
        )
        XCTAssertEqual(canonical?.memberIDs, members.map(\.memberID))
        if let canonical {
            assertNormalizedWeights(
                in: canonical,
                context: "canonical non-finite input"
            )
        }

        let rawBounds = CGRect(x: 3, y: 5, width: 811, height: 509)
        let rawHits = SplitLayoutGeometry.leafHits(in: raw, rect: rawBounds)
        XCTAssertEqual(rawHits.count, members.count)
        XCTAssertEqual(
            rawHits.reduce(0) { $0 + $1.rect.width * $1.rect.height },
            rawBounds.width * rawBounds.height,
            accuracy: 0.001
        )
        for hit in rawHits {
            XCTAssertTrue(hit.rect.origin.x.isFinite)
            XCTAssertTrue(hit.rect.origin.y.isFinite)
            XCTAssertTrue(hit.rect.width.isFinite)
            XCTAssertTrue(hit.rect.height.isFinite)
        }

        let flattened = try XCTUnwrap(
            SplitLayoutReconciler.canonicalizedForTiles(
                .split(
                    axis: .row,
                    weight: 1,
                    children: [
                        .split(
                            axis: .row,
                            weight: .greatestFiniteMagnitude,
                            children: [
                                .leaf(
                                    member: members[0],
                                    weight: .greatestFiniteMagnitude
                                ),
                                .leaf(member: members[1], weight: 0.01),
                            ]
                        ),
                        .leaf(member: members[2], weight: 0.01),
                    ]
                )
            )
        )
        guard case .split(_, _, let children) = flattened else {
            return XCTFail("Expected same-axis children to flatten")
        }
        XCTAssertGreaterThan(
            children[0].weightInParent,
            children[1].weightInParent
        )
        assertNormalizedWeights(in: flattened, context: "overflow-safe flatten")
    }

    func testCanonicalizationIsIdempotentAcrossTopologyPermutations() throws {
        let members = makeMembers(4)
        for permutation in permutations(of: members) {
            for (name, tree) in canonicalFourPaneTopologies(
                members: permutation
            ) {
                let first = try XCTUnwrap(
                    SplitLayoutReconciler.canonicalizedForTiles(tree),
                    "Failed to canonicalize \(name)"
                )
                let second = try XCTUnwrap(
                    SplitLayoutReconciler.canonicalizedForTiles(first),
                    "Failed to re-canonicalize \(name)"
                )

                XCTAssertEqual(first, second, name)
                XCTAssertEqual(first.memberIDs, permutation.map(\.memberID), name)
                XCTAssertEqual(Set(first.memberIDs).count, first.leafCount, name)
                assertCanonical(first, context: name)
                assertNormalizedWeights(in: first, context: name)
            }
        }
    }

    func testStructuralMutationMatrixPreservesIdentityAndRatios() throws {
        let members = makeMembers(4)
        let sides: [SplitDropSide] = [.left, .right, .top, .bottom]

        for kind in SplitLayoutKind.allCases {
            let tree = try XCTUnwrap(
                SplitLayoutFactory.make(kind: kind, members: members)
            )
            for dragged in members {
                for target in members where target != dragged {
                    for side in sides {
                        guard let moved = tree.movingMember(
                            dragged.memberID,
                            relativeTo: target.memberID,
                            side: side
                        ) else {
                            continue
                        }
                        XCTAssertEqual(Set(moved.memberIDs), Set(tree.memberIDs))
                        assertCanonical(
                            moved,
                            context: "\(kind) \(dragged) -> \(target) \(side)"
                        )
                        assertNormalizedWeights(
                            in: moved,
                            context: "\(kind) \(dragged) -> \(target) \(side)"
                        )
                    }
                }

                let reduced = try XCTUnwrap(
                    tree.removing(memberID: dragged.memberID)
                )
                XCTAssertEqual(
                    Set(reduced.memberIDs),
                    Set(tree.memberIDs).subtracting([dragged.memberID])
                )
                assertNormalizedWeights(
                    in: reduced,
                    context: "remove \(dragged) from \(kind)"
                )
            }
        }
    }

    func testGeometryExactlyPartitionsBoundsAcrossCanonicalTopologies() throws {
        let bounds = CGRect(x: 13, y: 17, width: 997, height: 613)
        let members = makeMembers(4)

        for (name, tree) in canonicalFourPaneTopologies(members: members) {
            let canonical = try XCTUnwrap(
                SplitLayoutReconciler.canonicalizedForTiles(tree)
            )
            let hits = SplitLayoutGeometry.leafHits(in: canonical, rect: bounds)

            XCTAssertEqual(
                Set(hits.map(\.memberID)),
                Set(members.map(\.memberID)),
                name
            )
            XCTAssertEqual(hits.count, members.count, name)
            XCTAssertEqual(
                hits.reduce(0) { $0 + $1.rect.width * $1.rect.height },
                bounds.width * bounds.height,
                accuracy: 0.001,
                name
            )
            for hit in hits {
                assertRectContained(hit.rect, in: bounds, context: name)
            }
            for firstIndex in hits.indices {
                for secondIndex in hits.indices where secondIndex > firstIndex {
                    let overlap = hits[firstIndex].rect.intersection(
                        hits[secondIndex].rect
                    )
                    XCTAssertTrue(
                        overlap.isNull || overlap.width * overlap.height < 0.001,
                        "Leaf rectangles overlap: \(name)"
                    )
                }
            }
        }
    }

    func testDropMutationMatrixPreservesCanonicalInvariants() throws {
        let members = makeMembers(5)
        let existing = Array(members.prefix(3))
        let incoming = members[3]
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .vertical, members: existing)
        )
        let hits = SplitLayoutGeometry.leafHits(in: tree, rect: bounds)

        for hit in hits {
            for side in [SplitDropSide.left, .right, .top, .bottom] {
                let target = SplitDropTarget(
                    targetMemberID: hit.memberID,
                    side: side,
                    targetRect: hit.rect,
                    planePath: hit.path,
                    intent: .siblingEdge
                )
                let resolved = try XCTUnwrap(
                    SplitLayoutDropMutation.resolve(
                        in: tree,
                        draggedMember: incoming,
                        target: target,
                        bounds: bounds
                    ),
                    "External insert failed for \(hit.memberID) \(side)"
                )
                XCTAssertEqual(
                    Set(resolved.layoutTree.memberIDs),
                    Set(existing.map(\.memberID) + [incoming.memberID])
                )
                assertCanonical(resolved.layoutTree, context: "external insert")
                assertEqualChildWeightsRecursively(
                    resolved.layoutTree,
                    context: "drop weights"
                )
            }
        }

        let replacement = members[4]
        let centerHit = try XCTUnwrap(hits.first)
        let centered = try XCTUnwrap(
            SplitLayoutDropMutation.resolve(
                in: tree,
                draggedMember: replacement,
                target: SplitDropTarget(
                    targetMemberID: centerHit.memberID,
                    side: .center,
                    targetRect: centerHit.rect,
                    previewStyle: .center,
                    planePath: centerHit.path,
                    intent: .paneCenter
                ),
                bounds: bounds
            )
        )
        XCTAssertEqual(
            Set(centered.layoutTree.memberIDs),
            Set(
                existing.map(\.memberID)
                    .filter { $0 != centerHit.memberID } + [replacement.memberID]
            )
        )
        assertNormalizedWeights(
            in: centered.layoutTree,
            context: "center replacement"
        )
    }

    private func makeMembers(_ count: Int) -> [SplitMember] {
        (0..<count).map { _ in .regularTab(UUID()) }
    }

    private func canonicalFourPaneTopologies(
        members: [SplitMember]
    ) -> [(String, SplitLayoutTree)] {
        func equalLeaves(
            _ axis: SplitAxis,
            _ members: ArraySlice<SplitMember>,
            weight: Double
        ) -> SplitLayoutTree {
            .split(
                axis: axis,
                weight: weight,
                children: members.map {
                    .leaf(
                        member: $0,
                        weight: 1 / Double(members.count)
                    )
                }
            )
        }

        var topologies: [(String, SplitLayoutTree)] = [
            (
                "4v",
                .split(
                    axis: .row,
                    weight: 1,
                    children: members.map { .leaf(member: $0, weight: 0.25) }
                )
            ),
            (
                "4h",
                .split(
                    axis: .column,
                    weight: 1,
                    children: members.map { .leaf(member: $0, weight: 0.25) }
                )
            ),
        ]

        for rootAxis in [SplitAxis.row, .column] {
            let childAxis: SplitAxis = rootAxis == .row ? .column : .row
            topologies.append(
                (
                    "2+2",
                    .split(
                        axis: rootAxis,
                        weight: 1,
                        children: [
                            equalLeaves(
                                childAxis,
                                members[0..<2],
                                weight: 0.5
                            ),
                            equalLeaves(
                                childAxis,
                                members[2..<4],
                                weight: 0.5
                            ),
                        ]
                    )
                )
            )
            topologies.append(
                (
                    "3+1",
                    .split(
                        axis: rootAxis,
                        weight: 1,
                        children: [
                            equalLeaves(
                                childAxis,
                                members[0..<3],
                                weight: 0.5
                            ),
                            .leaf(member: members[3], weight: 0.5),
                        ]
                    )
                )
            )
            for splitIndex in 0..<3 {
                var cursor = 0
                let children = (0..<3).map { index -> SplitLayoutTree in
                    if index == splitIndex {
                        let split = equalLeaves(
                            childAxis,
                            members[cursor..<cursor + 2],
                            weight: 1.0 / 3.0
                        )
                        cursor += 2
                        return split
                    }
                    defer { cursor += 1 }
                    return .leaf(
                        member: members[cursor],
                        weight: 1.0 / 3.0
                    )
                }
                topologies.append(
                    (
                        "1+2+1-\(splitIndex)",
                        .split(
                            axis: rootAxis,
                            weight: 1,
                            children: children
                        )
                    )
                )
            }
        }
        return topologies
    }

    private func assertCanonical(
        _ tree: SplitLayoutTree,
        context: String,
        parentAxis: SplitAxis? = nil,
        depth: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch tree {
        case .leaf:
            XCTAssertLessThanOrEqual(depth, 2, context, file: file, line: line)
        case .split(let axis, _, let children):
            XCTAssertLessThanOrEqual(depth, 1, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(
                children.count,
                2,
                context,
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                children.count,
                SplitGroup.maximumMembers,
                context,
                file: file,
                line: line
            )
            if let parentAxis {
                XCTAssertNotEqual(axis, parentAxis, context, file: file, line: line)
            }
            XCTAssertEqual(
                Set(tree.memberIDs).count,
                tree.leafCount,
                context,
                file: file,
                line: line
            )
            for child in children {
                assertCanonical(
                    child,
                    context: context,
                    parentAxis: axis,
                    depth: depth + 1,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertNormalizedWeights(
        in tree: SplitLayoutTree,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(_, _, let children) = tree else { return }
        XCTAssertEqual(
            children.reduce(0) { $0 + $1.weightInParent },
            1,
            accuracy: 0.000_001,
            context,
            file: file,
            line: line
        )
        for child in children {
            XCTAssertTrue(
                child.weightInParent.isFinite,
                context,
                file: file,
                line: line
            )
            XCTAssertGreaterThan(
                child.weightInParent,
                0,
                context,
                file: file,
                line: line
            )
            assertNormalizedWeights(
                in: child,
                context: context,
                file: file,
                line: line
            )
        }
    }

    private func assertEqualChildWeightsRecursively(
        _ tree: SplitLayoutTree,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(_, _, let children) = tree else { return }
        let expected = 1 / Double(children.count)
        for child in children {
            XCTAssertEqual(
                child.weightInParent,
                expected,
                accuracy: 0.0001,
                context,
                file: file,
                line: line
            )
            assertEqualChildWeightsRecursively(
                child,
                context: context,
                file: file,
                line: line
            )
        }
    }

    private func assertRectContained(
        _ rect: CGRect,
        in container: CGRect,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            rect.minX,
            container.minX - 0.0001,
            context,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            rect.minY,
            container.minY - 0.0001,
            context,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            rect.maxX,
            container.maxX + 0.0001,
            context,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            rect.maxY,
            container.maxY + 0.0001,
            context,
            file: file,
            line: line
        )
    }

    private func permutations<T>(of values: [T]) -> [[T]] {
        guard let first = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { suffix in
            (0...suffix.count).map { index in
                var permutation = suffix
                permutation.insert(first, at: index)
                return permutation
            }
        }
    }
}
