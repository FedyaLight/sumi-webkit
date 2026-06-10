//
//  SumiNativeMessagingPortControlling.swift
//  Sumi
//
//  Testable port surface for WKWebExtension.MessagePort relay sessions.
//

import Foundation
import WebKit

@MainActor
protocol SumiNativeMessagingPortControlling: AnyObject {
    var applicationIdentifier: String? { get }
    var isDisconnected: Bool { get }
    var messageHandler: ((Any?, (any Error)?) -> Void)? { get set }
    var disconnectHandler: (((any Error)?) -> Void)? { get set }
    func disconnect()
    func disconnect(throwing error: (any Error)?)
}

extension WKWebExtension.MessagePort: SumiNativeMessagingPortControlling {}
