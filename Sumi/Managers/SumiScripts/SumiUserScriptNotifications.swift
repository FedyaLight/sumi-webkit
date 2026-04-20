//
//  SumiUserScriptNotifications.swift
//  Sumi
//

import Foundation

extension Notification.Name {
    static let sumiUserScriptMenuCommandsDidChange = Notification.Name("SumiUserScriptMenuCommandsDidChange")
    /// Posted when a userscript reports `error` / `unhandledrejection` from the GM content world.
    static let sumiUserScriptRuntimeError = Notification.Name("SumiUserScriptRuntimeError")
}
