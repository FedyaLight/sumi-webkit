import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveRetirementRuntimeOracle {
    enum Hook {
        case none
        case attachmentABAOnCanRetire(Int)
        case terminalDrainOnCanRetire(Int)
        case attachmentABAOnCommittedBegin
        case actionOnCanRetire(Int, @MainActor () -> Void)
    }

    let window = BrowserWindowState()
    let hook: Hook
    private(set) var tabManager: BrowserManager!
    private(set) var runtime: RuntimePortRegistry!
    private(set) var pin: ShortcutPin!
    private(set) var liveTab: Tab!
    private(set) var canRetireCount = 0
    private(set) var normalDestroyCount = 0
    private(set) var aggregateDrainDestroyCount = 0
    private(set) var terminalDrainEntries = 0
    private(set) var events: [String] = []

    static func make(hook: Hook) throws -> Self {
        let oracle = Self(hook: hook)
        try oracle.install()
        return oracle
    }

    private init(hook: Hook) {
        self.hook = hook
    }

    private func install() throws {
        tabManager = BrowserManager()
        let repository = tabManager.webViewSessions
        let capabilities = TestRuntimePorts.RetirementCapabilities(
            canRetire: { [weak self] _ in
                guard let self else { return false }
                canRetireCount += 1
                switch hook {
                case .attachmentABAOnCanRetire(let call)
                    where call == canRetireCount:
                    replaceAttachment()
                case .terminalDrainOnCanRetire(let call)
                    where call == canRetireCount:
                    terminalDrainEntries = repository
                        .takeAllWebViewsForTerminalShutdown().count
                case .actionOnCanRetire(let call, let action)
                    where call == canRetireCount:
                    action()
                case .none, .attachmentABAOnCanRetire,
                        .terminalDrainOnCanRetire,
                        .attachmentABAOnCommittedBegin,
                        .actionOnCanRetire:
                    break
                }
                return true
            },
            beginCommitted: { [weak self] _ in
                guard let self else { return false }
                events.append("committedBegin")
                if case .attachmentABAOnCommittedBegin = hook {
                    replaceAttachment()
                }
                return true
            },
            committedRetirementIsExact: { _ in true },
            destroy: { [weak self] _ in
                self?.normalDestroyCount += 1
                self?.events.append("normalDestroy")
            },
            destroyAfterTerminalDrain: { [weak self] _ in
                self?.aggregateDrainDestroyCount += 1
                self?.events.append("aggregateDrainDestroy")
            }
        )
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: capabilities
        )
        runtime = TestRuntimePorts.make(
            windowState: { [window] id in id == window.id ? window : nil },
            windows: { [window] in [(window.id, window)] },
            windowStates: { [window] in [window] },
            webViewLifecycle: lifecycle,
            notifyTabClosedIfLoaded: { [weak self] _ in
                self?.events.append("extension")
            },
            persistWindowSession: { [weak self] _ in
                self?.events.append("persist")
            }
        )
        tabManager.runtimePortConnection.attach(runtime)
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
        pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(), role: .spacePinned, spaceId: space.id, index: 0,
                launchURL: URL(string: "https://runtime-oracle.example")!,
                title: "Runtime Oracle"
            ),
            at: 0
        ))
        liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                pin, in: window.id, currentSpaceId: space.id
            )
        )
        liveTab.replaceUntrackedWebView(WKWebView())
        window.currentSpaceId = space.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = pin.id
        window.currentShortcutPinRole = pin.role
    }

    private func replaceAttachment() {
        tabManager.runtimePortConnection.detach()
        tabManager.runtimePortConnection.attach(runtime)
    }
}
