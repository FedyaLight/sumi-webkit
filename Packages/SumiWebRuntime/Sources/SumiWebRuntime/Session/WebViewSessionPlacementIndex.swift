import Foundation

/// Identity-only projection of active placement. The canonical records retain
/// WebViews; this index makes reverse residence and window queries O(1).
@MainActor
struct WebViewSessionPlacementIndex {
    private(set) var residences: [ObjectIdentifier: WebViewResidence] = [:]
    private var tabIDsByWindowID: [UUID: Set<UUID>] = [:]

    var isEmpty: Bool { residences.isEmpty }

    func residence(of object: AnyObject) -> WebViewResidence? {
        residences[ObjectIdentifier(object)]
    }

    func residence(with identifier: ObjectIdentifier) -> WebViewResidence? {
        residences[identifier]
    }

    func trackedTabIDs(in windowID: UUID) -> Set<UUID> {
        tabIDsByWindowID[windowID] ?? []
    }

    mutating func install(
        _ residence: WebViewResidence,
        for object: AnyObject
    ) {
        residences[ObjectIdentifier(object)] = residence
    }

    mutating func remove(
        _ object: AnyObject?,
        expected: WebViewResidence
    ) {
        guard let object else { return }
        let identifier = ObjectIdentifier(object)
        if residences[identifier] == expected {
            residences.removeValue(forKey: identifier)
        }
    }

    mutating func replaceWindowMembership(
        for tabID: UUID,
        previousWindowIDs: Set<UUID>,
        replacementWindowIDs: Set<UUID>
    ) {
        for windowID in previousWindowIDs.subtracting(replacementWindowIDs) {
            guard var tabIDs = tabIDsByWindowID[windowID] else {
                assertionFailure("Missing tracked-window index during removal")
                continue
            }
            assert(tabIDs.remove(tabID) != nil)
            if tabIDs.isEmpty {
                tabIDsByWindowID.removeValue(forKey: windowID)
            } else {
                tabIDsByWindowID[windowID] = tabIDs
            }
        }
        for windowID in replacementWindowIDs.subtracting(previousWindowIDs) {
            let inserted = tabIDsByWindowID[windowID, default: []]
                .insert(tabID).inserted
            assert(inserted)
        }
    }

    mutating func removeAll() {
        residences.removeAll()
        tabIDsByWindowID.removeAll()
    }

    func assertMatches(
        _ records: [UUID: WebViewSessionPlacementRecord],
        context: StaticString
    ) {
        #if DEBUG
            var expectedResidences: [ObjectIdentifier: WebViewResidence] = [:]
            var expectedWindowIndex: [UUID: Set<UUID>] = [:]
            for (tabID, record) in records {
                assertRecordShape(record, context: context)
                Self.record(
                    record.parkedWebView,
                    residence: .parked(tabID: tabID),
                    in: &expectedResidences,
                    context: context
                )
                Self.record(
                    record.untrackedWebView,
                    residence: .untracked(tabID: tabID),
                    in: &expectedResidences,
                    context: context
                )
                for (windowID, webView) in record.windowWebViews {
                    Self.record(
                        webView,
                        residence: .window(
                            .init(tabID: tabID, windowID: windowID)
                        ),
                        in: &expectedResidences,
                        context: context
                    )
                    expectedWindowIndex[windowID, default: []].insert(tabID)
                }
            }
            assert(
                expectedResidences == residences,
                "Active forward/reverse indexes diverged during \(context)"
            )
            assert(
                expectedWindowIndex == tabIDsByWindowID,
                "Active window index diverged during \(context)"
            )
        #else
            _ = records
            _ = context
        #endif
    }

    private func assertRecordShape(
        _ record: WebViewSessionPlacementRecord,
        context: StaticString
    ) {
        assert(
            record.untrackedWebView == nil || record.windowWebViews.isEmpty,
            "Untracked and windowed placements coexist during \(context)"
        )
        if record.windowWebViews.isEmpty {
            assert(
                record.primaryWindowID == nil,
                "Empty window set has a primary during \(context)"
            )
        } else if let primaryWindowID = record.primaryWindowID {
            assert(
                record.windowWebViews[primaryWindowID] != nil,
                "Primary window has no WebView during \(context)"
            )
        } else {
            assertionFailure("Windowed session has no primary during \(context)")
        }
    }

    private static func record(
        _ object: AnyObject?,
        residence: WebViewResidence,
        in expectedResidences: inout [ObjectIdentifier: WebViewResidence],
        context: StaticString
    ) {
        guard let object else { return }
        let identifier = ObjectIdentifier(object)
        assert(
            expectedResidences[identifier] == nil,
            "WKWebView has multiple active residences during \(context)"
        )
        expectedResidences[identifier] = residence
    }
}
