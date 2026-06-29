import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SumiBoostEditorSessionActions {
    private weak var tab: Tab?
    private weak var profile: Profile?
    private weak var windowState: BrowserWindowState?
    private weak var module: SumiBoostsModule?
    private let onClose: @MainActor () -> Void
    private var didDelete = false

    init(
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState,
        module: SumiBoostsModule,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.tab = tab
        self.profile = profile
        self.windowState = windowState
        self.module = module
        self.onClose = onClose
    }

    var isEphemeral: Bool {
        profile?.isEphemeral == true || tab?.isEphemeral == true
    }

    func close(boost: SumiBoost) {
        module?.stopZapSelection()
        guard !didDelete else { return }
        // If the user made changes, the boost is persisted and active; we must
        // re-sync the atDocumentStart WKUserScript so the final state takes
        // effect on the next navigation, and flush any debounced disk write.
        // If nothing changed, discard the ephemeral draft instead.
        if boost.data.changeWasMade {
            module?.reinstallUserScriptsAfterEdit(profileId: boost.profileId, host: boost.host)
        } else {
            module?.discardUnchangedDraft(boost)
        }
    }

    func dismiss() {
        onClose()
    }

    func delete(boost: SumiBoost) {
        didDelete = true
        module?.deleteBoost(boost, isEphemeral: isEphemeral)
        onClose()
    }

    func update(
        boost: SumiBoost,
        refreshPath: SumiBoostsModule.RefreshPath = .liveState,
        _ mutate: (inout SumiBoostData) -> Void
    ) -> SumiBoost? {
        module?.updateBoost(
            boost,
            isEphemeral: isEphemeral,
            markChanged: true,
            refreshPath: refreshPath,
            mutate: mutate
        )
    }

    func startZap(
        boost: SumiBoost,
        onSelector: @escaping @MainActor (SumiBoost) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let tab, let windowState else { return false }
        return module?.startZapSelection(
            for: boost,
            tab: tab,
            windowState: windowState,
            isEphemeral: isEphemeral,
            onSelector: onSelector,
            onFinish: onFinish
        ) ?? false
    }

    func stopZap() {
        module?.stopZapSelection()
    }

    func previewZap(_ selector: String, isHighlighted: Bool) {
        guard let tab, let windowState else { return }
        module?.previewZapSelector(selector, isHighlighted: isHighlighted, tab: tab, windowState: windowState)
    }

    func exportJSON(
        boost: SumiBoost,
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard let module else { return }
        do {
            let data = try module.exportData(for: boost)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(boost.data.boostName).sumi-boost.json"
            savePanel.begin { [weak self] response in
                guard response == .OK, let url = savePanel.url else { return }
                do {
                    try data.write(to: url, options: [.atomic])
                } catch {
                    Task { @MainActor [weak self] in
                        guard self != nil else { return }
                        onError(error.localizedDescription)
                    }
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    func importJSON(
        onImported: @escaping @MainActor (SumiBoost) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        guard let tab, let module else { return }
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else {
                return
            }
            do {
                let data = try Data(contentsOf: url)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let imported = try module.importBoost(from: data, tab: tab, profile: self.profile)
                        onImported(imported)
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    onError(message)
                }
            }
        }
    }

    func openInspector() {
        module?.browserManager?.openWebInspector()
    }
}
