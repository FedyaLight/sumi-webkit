//
//  SafariExtensionNativeMessagingHost.swift
//  Sumi
//
//  Legacy entry point — delegates to SumiNativeMessagingRelay.
//

import Foundation
import WebKit

typealias SafariExtensionNativeMessagingHost = SumiNativeMessagingRelay

extension SumiNativeMessagingRelay {
    enum LegacyErrorCode {
        static var hostRelayUnavailable: Int {
            ErrorCode.companionAppProtocolUnknown.rawValue
        }
    }
}
