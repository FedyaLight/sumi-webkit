//
//  SumiFullscreenController.swift
//  Sumi
//
//  Copied closely from DuckDuckGo for macOS FullscreenController.swift,
//  used under the Apache License, Version 2.0.
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//  See: https://www.apache.org/licenses/LICENSE-2.0
//

import AppKit
import ObjectiveC.runtime
import WebKit

@MainActor
final class SumiFullscreenController {

    // List of hosts where ESC doesn't exit fullscreen.
    static var hosts = [
        "docs.google.com"
    ]

    private(set) var shouldPreventFullscreenExit: Bool = false

    func resetFullscreenExitFlag() {
        shouldPreventFullscreenExit = false
    }

    func handleEscapePress(host: String?) {
        if let host, Self.hosts.contains(host) {
            // Website is handling ESC. Stay in fullscreen.
            shouldPreventFullscreenExit = true
        }
    }

    func manuallyExitFullscreen(window: NSWindow?) {
        guard let window, window.styleMask.contains(.fullScreen) else { return }

        // Exit full screen.
        window.toggleFullScreen(nil)
    }
}

private enum SumiFullscreenControllerAssociatedKeys {
    static var controller: UInt8 = 0
    static var lifecycle: UInt8 = 0
}

@MainActor
private final class SumiFullscreenWindowLifecycle: NSObject {
    weak var window: NSWindow?
    weak var controller: SumiFullscreenController?
    private var willExitObserver: NSObjectProtocol?

    init(window: NSWindow, controller: SumiFullscreenController) {
        self.window = window
        self.controller = controller
        super.init()

        willExitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated {
                controller?.resetFullscreenExitFlag()
            }
        }
    }

    deinit {
        if let willExitObserver {
            NotificationCenter.default.removeObserver(willExitObserver)
        }
    }
}

extension NSWindow {
    @MainActor
    var sumiFullscreenController: SumiFullscreenController {
        installSumiFullscreenControllerIfNeeded()
    }

    @MainActor
    @discardableResult
    func installSumiFullscreenControllerIfNeeded() -> SumiFullscreenController {
        if let controller = objc_getAssociatedObject(
            self,
            &SumiFullscreenControllerAssociatedKeys.controller
        ) as? SumiFullscreenController {
            return controller
        }

        let controller = SumiFullscreenController()
        let lifecycle = SumiFullscreenWindowLifecycle(window: self, controller: controller)
        objc_setAssociatedObject(
            self,
            &SumiFullscreenControllerAssociatedKeys.controller,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        objc_setAssociatedObject(
            self,
            &SumiFullscreenControllerAssociatedKeys.lifecycle,
            lifecycle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return controller
    }
}
