//
//  AuxiliaryWebViewFactory.swift
//  Sumi
//

import WebKit

@MainActor
enum AuxiliaryWebViewFactory {
    static func makeWebViewPreservingWebKitConfiguration(
        _ configuration: WKWebViewConfiguration
    ) -> FocusableWKWebView {
        FocusableWKWebView(frame: .zero, configuration: configuration)
    }
}
