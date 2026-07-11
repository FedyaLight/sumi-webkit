//
//  WebViewWebKitClosePreparation.swift
//  Sumi
//
//  Describes the WebView runtime portion of a WebKit close request.
//

import Foundation

public enum WebViewWebKitClosePreparation {
    case deferred
    case ready(trackedOwner: TrackedWebViewOwner?)
}
