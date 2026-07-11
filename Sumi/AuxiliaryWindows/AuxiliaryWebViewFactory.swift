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
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        // WebKit child configurations inherit the normal source controller.
        // Surface classification belongs to the materialized auxiliary view,
        // while every physical WebKit configuration property remains intact.
        webView.configuration.sumiIsNormalTabWebViewConfiguration = false
        return webView
    }
}
