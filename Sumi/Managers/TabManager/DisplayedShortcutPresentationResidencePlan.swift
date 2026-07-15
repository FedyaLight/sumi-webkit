import Foundation

/// Complete exact presentation admission for a displayed shortcut conversion.
/// Construction finishes before the source Tab or any durable container moves.
@MainActor
struct DisplayedShortcutPresentationResidencePlan {
    struct Entry {
        let window: BrowserWindowState
        let spaceID: UUID
        let page: LiveShortcutPresentationPageReceipt
    }

    let pinID: UUID
    let sourceTab: Tab
    let source: Entry
    let replicas: [Entry]

    init?(
        pin: ShortcutPin,
        authorization: AuthorizedDisplayedTabShortcutConversion,
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner
    ) {
        let first = authorization.plan.firstWindow
        var windows = [first]
        var windowIDs: Set<UUID> = [first.id]
        for window in authorization.presentationWindows {
            if window.id == first.id {
                guard window === first else { return nil }
                continue
            }
            guard windowIDs.insert(window.id).inserted else { return nil }
            windows.append(window)
        }

        var entries: [Entry] = []
        for window in windows {
            guard let spaceID = pin.spaceId ?? window.currentSpaceId,
                  window.currentSpaceId == spaceID,
                  let page = resolution.presentationPageReceipt(
                      for: pin,
                      windowID: window.id,
                      presentationSpaceID: spaceID
                  ) else { return nil }
            entries.append(Entry(
                window: window,
                spaceID: spaceID,
                page: page
            ))
        }
        guard let source = entries.first,
              source.window === first,
              source.page.page.windowID == source.window.id,
              registry.entry(containing: authorization.tab) == nil,
              registry.tab(for: pin.id, in: source.window.id) == nil,
              entries.dropFirst().allSatisfy({ entry in
                  registry.tab(for: pin.id, in: entry.window.id) == nil
              }) else { return nil }
        pinID = pin.id
        sourceTab = authorization.tab
        self.source = source
        replicas = Array(entries.dropFirst())
    }

    func acceptsCurrentResidences(
        for pin: ShortcutPin,
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner
    ) -> Bool {
        guard pin.id == pinID,
              source.page.page.windowID == source.window.id,
              registry.entry(containing: sourceTab) == nil,
              registry.tab(for: pin.id, in: source.window.id) == nil
        else { return false }
        return ([source] + replicas).allSatisfy { planned in
            planned.window.currentSpaceId == planned.spaceID
                && resolution.presentationPageReceipt(
                    for: pin,
                    windowID: planned.window.id,
                    presentationSpaceID: planned.spaceID
                ) == planned.page
                && (planned.window === source.window
                    || registry.tab(
                        for: pin.id,
                        in: planned.window.id
                    ) == nil)
        }
    }
}
