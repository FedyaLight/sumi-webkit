//
//  NSTextField+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSTextField {
    var sumi_chromeIsFirstResponder: Bool {
        window?.firstResponder === currentEditor()
    }

    var sumi_findIsFirstResponder: Bool {
        sumi_chromeIsFirstResponder
    }
}
