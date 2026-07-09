//
//  WebViewCoordinatorWebKitClosePreparation.swift
//  Sumi
//
//  Describes the coordinator-owned portion of a WebKit close request.
//

import Foundation

public enum WebViewCoordinatorWebKitClosePreparation {
    case deferred
    case ready(trackedOwner: TrackedWebViewOwner?)
}
