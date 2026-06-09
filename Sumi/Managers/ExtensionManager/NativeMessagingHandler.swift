//
//  NativeMessagingHandler.swift
//  Sumi
//
//  Product native messaging remains unavailable. The DEBUG/internal fixture
//  Product native messaging remains unavailable; this handler tears down ports safely.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
final class NativeMessagingHandler: NSObject {
    func disconnect() {}
}
