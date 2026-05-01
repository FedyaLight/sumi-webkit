//
//  URLBarBookmarkControls.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension URLBarView {
    func handleBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest?) {
        guard let request,
              request.windowID == windowState.id,
              request.tabID == currentTab?.id
        else { return }

        closeZoomPopover()
        isHubPresented = true
    }

}
