import AppKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionAnchorStore {
    private static let maxAnchorsPerExtension = 32

    private var anchorsByExtensionID: [String: [WeakAnchor]] = [:]
    private var observerTokensByExtensionID:
        [String: [ObjectIdentifier: NSObjectProtocol]] = [:]

    var extensionIDs: [String] {
        Array(anchorsByExtensionID.keys)
    }

    var isEmpty: Bool {
        anchorsByExtensionID.isEmpty
    }

    func anchorCount(for extensionId: String) -> Int {
        anchorsByExtensionID[extensionId]?.count ?? 0
    }

    func setAnchor(for extensionId: String, anchorView: NSView) {
        pruneAnchors(for: extensionId, keeping: anchorView)

        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        var anchors = anchorsByExtensionID[extensionId] ?? []

        if let index = anchors.firstIndex(where: { $0.view === anchorView }) {
            anchors[index] = anchor
        } else {
            anchors.append(anchor)
        }
        anchorsByExtensionID[extensionId] = anchors

        installFrameObserverIfNeeded(for: extensionId, anchorView: anchorView)
        enforceAnchorLimit(for: extensionId, keeping: anchorView)
    }

    func clearAnchors(for extensionId: String) {
        removeAnchorObservers(for: extensionId)
        anchorsByExtensionID.removeValue(forKey: extensionId)
    }

    func liveAnchorView(
        for extensionId: String,
        matching targetWindow: NSWindow?,
        isReady: @MainActor (NSView?) -> Bool
    ) -> NSView? {
        pruneAnchors(for: extensionId)
        guard let anchors = anchorsByExtensionID[extensionId] else { return nil }

        if let targetWindow,
           let match = anchors.first(where: {
               $0.window === targetWindow && isReady($0.view)
           }),
           let view = match.view {
            return view
        }

        return anchors.first(where: {
            isReady($0.view)
        })?.view
    }

    private func installFrameObserverIfNeeded(
        for extensionId: String,
        anchorView: NSView
    ) {
        let viewIdentifier = ObjectIdentifier(anchorView)
        anchorView.postsFrameChangedNotifications = true

        if observerTokensByExtensionID[extensionId]?[viewIdentifier] != nil {
            return
        }

        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self, weak anchorView] _ in
            guard let anchorView else { return }
            Task { @MainActor [weak self, weak anchorView] in
                guard let self, let anchorView else { return }
                self.refreshAnchorWindow(for: extensionId, anchorView: anchorView)
            }
        }

        observerTokensByExtensionID[extensionId, default: [:]][viewIdentifier] =
            token
    }

    private func refreshAnchorWindow(
        for extensionId: String,
        anchorView: NSView
    ) {
        guard let index = anchorsByExtensionID[extensionId]?.firstIndex(where: {
            $0.view === anchorView
        }) else {
            return
        }

        anchorsByExtensionID[extensionId]?[index] = WeakAnchor(
            view: anchorView,
            window: anchorView.window
        )
        pruneAnchors(for: extensionId, keeping: anchorView)
    }

    private func removeAnchorObservers(for extensionId: String) {
        guard let tokens = observerTokensByExtensionID.removeValue(
            forKey: extensionId
        ) else {
            return
        }

        for (_, token) in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func pruneAnchors(
        for extensionId: String,
        keeping anchorView: NSView? = nil
    ) {
        guard var anchors = anchorsByExtensionID[extensionId] else {
            return
        }

        anchors.removeAll { anchor in
            guard let view = anchor.view else { return true }
            if let anchorView, view === anchorView {
                return false
            }
            return anchor.window == nil || view.window == nil
        }

        if anchors.isEmpty {
            anchorsByExtensionID.removeValue(forKey: extensionId)
        } else {
            anchorsByExtensionID[extensionId] = anchors
        }

        let liveViewIDs = Set(anchors.compactMap { anchor -> ObjectIdentifier? in
            guard let view = anchor.view else { return nil }
            return ObjectIdentifier(view)
        })
        let keptViewID = anchorView.map(ObjectIdentifier.init)

        guard var tokens = observerTokensByExtensionID[extensionId] else {
            return
        }

        for viewID in Array(tokens.keys) {
            guard liveViewIDs.contains(viewID) == false,
                  viewID != keptViewID
            else {
                continue
            }
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            observerTokensByExtensionID.removeValue(forKey: extensionId)
        } else {
            observerTokensByExtensionID[extensionId] = tokens
        }
    }

    private func enforceAnchorLimit(
        for extensionId: String,
        keeping anchorView: NSView
    ) {
        guard var anchors = anchorsByExtensionID[extensionId],
              anchors.count > Self.maxAnchorsPerExtension else {
            return
        }

        var removedViewIDs: [ObjectIdentifier] = []
        while anchors.count > Self.maxAnchorsPerExtension {
            guard let removalIndex = anchors.firstIndex(where: { anchor in
                guard let view = anchor.view else { return true }
                return view !== anchorView
            }) else {
                break
            }

            if let view = anchors[removalIndex].view {
                removedViewIDs.append(ObjectIdentifier(view))
            }
            anchors.remove(at: removalIndex)
        }

        anchorsByExtensionID[extensionId] = anchors

        guard var tokens = observerTokensByExtensionID[extensionId] else {
            return
        }

        for viewID in removedViewIDs {
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            observerTokensByExtensionID.removeValue(forKey: extensionId)
        } else {
            observerTokensByExtensionID[extensionId] = tokens
        }
    }
}
