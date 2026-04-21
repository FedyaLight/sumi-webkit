//
//  SumiUserScriptMessageBroker.swift
//  Sumi
//
//  Lightweight per-WebView broker for privileged userscript APIs.
//  GM API methods are routed from `UserScriptGMBridge` via `UserScriptGMDispatch` in SumiUserScriptGMSubfeatures.swift.
//

import Foundation
import WebKit

@MainActor
final class SumiUserScriptMessageBroker {
    struct Entry {
        let scriptId: UUID
        let bridge: UserScriptGMBridge
        let contentWorld: WKContentWorld
    }

    let webViewId: UUID
    private let profileId: UUID?
    private weak var tabHandler: SumiScriptsTabHandler?
    private var entries: [UUID: Entry] = [:]

    init(
        webViewId: UUID,
        profileId: UUID?,
        tabHandler: SumiScriptsTabHandler?
    ) {
        self.webViewId = webViewId
        self.profileId = profileId
        self.tabHandler = tabHandler
    }

    @discardableResult
    func registerBridge(
        for script: UserScript,
        contentWorld: WKContentWorld,
        in controller: WKUserContentController
    ) -> UserScriptGMBridge {
        if let existing = entries[script.id] {
            return existing.bridge
        }

        let bridge = UserScriptGMBridge(
            script: script,
            profileId: profileId,
            contentWorld: contentWorld,
            tabOpenHandler: tabHandler
        )
        controller.add(bridge, contentWorld: contentWorld, name: bridge.messageHandlerName)
        entries[script.id] = Entry(scriptId: script.id, bridge: bridge, contentWorld: contentWorld)
        return bridge
    }

    func bridge(for script: UserScript) -> UserScriptGMBridge? {
        entries[script.id]?.bridge
    }

    func unregisterAll(from controller: WKUserContentController) {
        for entry in entries.values {
            controller.removeScriptMessageHandler(
                forName: entry.bridge.messageHandlerName,
                contentWorld: entry.contentWorld
            )
        }
        entries.removeAll()
    }
}
