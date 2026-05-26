//
//  NativeMessagingHandler.swift
//  Sumi
//
//  Product native messaging remains unavailable. The DEBUG/internal fixture
//  bridge lives in ChromeMV3NativeMessagingInternalRuntime.swift.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
final class NativeMessagingHandler: NSObject {
    func disconnect() {}
}
