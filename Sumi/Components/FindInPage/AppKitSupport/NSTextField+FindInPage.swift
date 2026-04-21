//
//  NSTextField+FindInPage.swift
//  Sumi
//
//  SPDX-License-Identifier: Apache-2.0
//

import AppKit

extension NSTextField {
    var sumi_findIsFirstResponder: Bool {
        window?.firstResponder === currentEditor()
    }
}
