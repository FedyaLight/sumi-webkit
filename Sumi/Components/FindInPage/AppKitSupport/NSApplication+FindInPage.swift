//
//  NSApplication+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSApplication {
    var sumi_findIsReturnOrEnterPressed: Bool {
        guard let event = currentEvent,
              case .keyDown = event.type
        else { return false }
        return event.keyCode == 36 || event.keyCode == 76
    }
}
