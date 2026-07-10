import XCTest

@testable import Sumi

@MainActor
final class SplitLayoutInvariantTests: SplitGroupTestCase {
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
        let ids = makeIDs(4)
        let raw = SplitLayoutTree.split(
            axis: .row,
            size: 1,
            children: [
                .leaf(tabId: ids[0], size: .nan),
                .split(
                    axis: .column,
                    size: .greatestFiniteMagnitude,
                    children: [
                        .leaf(tabId: ids[1], size: -100),
                        .leaf(tabId: ids[2], size: .greatestFiniteMagnitude),
                    ]
                ),
                .leaf(tabId: ids[3], size: .infinity),
            ]
        )

        let normalized = SplitLayoutSizing.normalizingSiblingSizes(in: raw)
        let canonical = SplitLayoutReconciler.canonicalizedForTiles(raw)

        XCTAssertEqual(normalized.tabIds, ids)
        assertNormalizedRatios(in: normalized, context: "non-finite and non-positive input")
        XCTAssertEqual(canonical?.tabIds, ids)
        if let canonical {
            assertNormalizedRatios(in: canonical, context: "canonical non-finite input")
        }

        let rawBounds = CGRect(x: 3, y: 5, width: 811, height: 509)
        let rawHits = SplitLayoutGeometry.leafHits(in: raw, rect: rawBounds)
        XCTAssertEqual(rawHits.count, ids.count)
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
                    size: 1,
                    children: [
                        .split(
                            axis: .row,
                            size: .greatestFiniteMagnitude,
                            children: [
                                .leaf(tabId: ids[0], size: .greatestFiniteMagnitude),
                                .leaf(tabId: ids[1], size: 0.01),
                            ]
                        ),
                        .leaf(tabId: ids[2], size: 0.01),
                    ]
                )
            )
        )
        if case .split(_, _, let children) = flattened {
            XCTAssertGreaterThan(children[0].sizeInParent, children[1].sizeInParent)
            assertNormalizedRatios(in: flattened, context: "overflow-safe flatten")
        } else {
            XCTFail("Expected same-axis children to flatten")
        }
    }

    func testCanonicalizationIsIdempotentAndIdentityStableAcrossTopologyPermutations() throws {
        let ids = makeIDs(4)
        for permutation in permutations(of: ids) {
            for (name, tree) in canonicalFourPaneTopologies(ids: permutation) {
                let first = try XCTUnwrap(
                    SplitLayoutReconciler.canonicalizedForTiles(tree),
                    "Failed to canonicalize \(name)"
                )
                let second = try XCTUnwrap(
                    SplitLayoutReconciler.canonicalizedForTiles(first),
                    "Failed to re-canonicalize \(name)"
                )

                XCTAssertEqual(first, second, "Canonicalization must be idempotent: \(name)")
                XCTAssertEqual(first.tabIds, permutation, "Leaf identity/order changed: \(name)")
                XCTAssertEqual(Set(first.tabIds).count, first.tabIds.count, "Duplicate leaf: \(name)")
                assertZenCanonicalTree(first, name)
                assertNormalizedRatios(in: first, context: name)
            }
        }
    }

    func testStructuralMutationMatrixPreservesIdentityAndCanonicalRatios() throws {
        let ids = makeIDs(4)
        let sides: [SplitDropSide] = [.left, .right, .top, .bottom]

        for kind in SplitLayoutKind.allCases {
            let tree = SplitLayoutFactory.make(kind: kind, tabIds: ids)
            for dragged in ids {
                for target in ids where target != dragged {
                    for side in sides {
                        guard let moved = tree.movingTab(
                            dragged,
                            relativeTo: target,
                            side: side
                        ) else {
                            continue
                        }
                        XCTAssertEqual(Set(moved.tabIds), Set(ids))
                        XCTAssertEqual(moved.tabIds.count, ids.count)
                        XCTAssertEqual(Set(moved.tabIds).count, moved.tabIds.count)
                        assertZenCanonicalTree(
                            moved,
                            "\(kind) \(dragged) -> \(target) \(side)"
                        )
                        assertNormalizedRatios(
                            in: moved,
                            context: "\(kind) \(dragged) -> \(target) \(side)"
                        )
                    }
                }

                let reduced = try XCTUnwrap(tree.removing(tabId: dragged))
                XCTAssertEqual(Set(reduced.tabIds), Set(ids).subtracting([dragged]))
                XCTAssertEqual(reduced.tabIds.count, ids.count - 1)
                assertNormalizedRatios(in: reduced, context: "remove \(dragged) from \(kind)")
            }
        }
    }

    func testGeometryExactlyPartitionsBoundsAcrossCanonicalTopologies() throws {
        let bounds = CGRect(x: 13, y: 17, width: 997, height: 613)
        let ids = makeIDs(4)

        for (name, tree) in canonicalFourPaneTopologies(ids: ids) {
            let canonical = try XCTUnwrap(
                SplitLayoutReconciler.canonicalizedForTiles(tree)
            )
            let hits = SplitLayoutGeometry.leafHits(in: canonical, rect: bounds)

            XCTAssertEqual(Set(hits.map(\.tabId)), Set(ids), name)
            XCTAssertEqual(hits.count, ids.count, name)
            XCTAssertEqual(
                hits.reduce(0) { $0 + $1.rect.width * $1.rect.height },
                bounds.width * bounds.height,
                accuracy: 0.001,
                name
            )
            for hit in hits {
                assertRectContained(hit.rect, in: bounds, name)
            }
            for firstIndex in hits.indices {
                for secondIndex in hits.indices where secondIndex > firstIndex {
                    let overlap = hits[firstIndex].rect.intersection(hits[secondIndex].rect)
                    XCTAssertTrue(
                        overlap.isNull || overlap.width * overlap.height < 0.001,
                        "Leaf rectangles overlap: \(name)"
                    )
                }
            }
        }
    }

    func testCodableRoundTripPreservesCanonicalIdentityAndRatios() throws {
        let ids = makeIDs(4)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for (name, tree) in canonicalFourPaneTopologies(ids: ids) {
            let canonical = try XCTUnwrap(
                SplitLayoutReconciler.canonicalizedForTiles(tree)
            )
            let decoded = try decoder.decode(
                SplitLayoutTree.self,
                from: encoder.encode(canonical)
            )

            XCTAssertEqual(decoded, canonical, name)
            XCTAssertEqual(decoded.tabIds, ids, name)
            assertNormalizedRatios(in: decoded, context: name)
        }
    }

    func testDropMutationMatrixPreservesCanonicalInvariants() throws {
        let ids = makeIDs(5)
        let existingIds = Array(ids.prefix(3))
        let incoming = ids[3]
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let tree = SplitLayoutFactory.make(kind: .vertical, tabIds: existingIds)
        let hits = SplitLayoutGeometry.leafHits(in: tree, rect: bounds)

        for hit in hits {
            for side in [SplitDropSide.left, .right, .top, .bottom] {
                let target = SplitDropTarget(
                    tabId: hit.tabId,
                    side: side,
                    targetRect: hit.rect,
                    planePath: hit.path,
                    intent: .siblingEdge
                )
                let resolved = try XCTUnwrap(
                    SplitLayoutDropMutation.resolve(
                        in: tree,
                        draggedTabId: incoming,
                        target: target,
                        bounds: bounds
                    ),
                    "External insert failed for \(hit.tabId) \(side)"
                )
                XCTAssertEqual(Set(resolved.layoutTree.tabIds), Set(existingIds + [incoming]))
                XCTAssertEqual(resolved.layoutTree.tabIds.count, 4)
                assertZenCanonicalTree(
                    resolved.layoutTree,
                    "external insert \(hit.tabId) \(side)"
                )
                assertEqualChildSizesRecursively(
                    resolved.layoutTree,
                    "drop sizes \(hit.tabId) \(side)"
                )
            }
        }

        let replacement = ids[4]
        let centerHit = try XCTUnwrap(hits.first)
        let centerTarget = SplitDropTarget(
            tabId: centerHit.tabId,
            side: .center,
            targetRect: centerHit.rect,
            previewStyle: .center,
            planePath: centerHit.path,
            intent: .paneCenter
        )
        let centered = try XCTUnwrap(
            SplitLayoutDropMutation.resolve(
                in: tree,
                draggedTabId: replacement,
                target: centerTarget,
                bounds: bounds
            )
        )
        XCTAssertEqual(
            Set(centered.layoutTree.tabIds),
            Set(existingIds.filter { $0 != centerHit.tabId } + [replacement])
        )
        assertNormalizedRatios(in: centered.layoutTree, context: "center replacement")
    }

    private func assertNormalizedRatios(
        in tree: SplitLayoutTree,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(_, _, let children) = tree else { return }
        if !children.isEmpty {
            XCTAssertEqual(
                children.reduce(0) { $0 + $1.sizeInParent },
                1,
                accuracy: 0.000_001,
                context,
                file: file,
                line: line
            )
        }
        for child in children {
            XCTAssertTrue(child.sizeInParent.isFinite, context, file: file, line: line)
            XCTAssertGreaterThan(child.sizeInParent, 0, context, file: file, line: line)
            assertNormalizedRatios(
                in: child,
                context: context,
                file: file,
                line: line
            )
        }
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
