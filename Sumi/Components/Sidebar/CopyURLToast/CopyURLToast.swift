//
//  CopyURLToast.swift
//  Sumi
//
//  Created on 2025-01-XX.
//

import SwiftUI

struct CopyURLToast: View {
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ToastView {
            ToastContent(icon: "checkmark.circle.fill", text: "Copied Current URL")
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                windowState.isShowingCopyURLToast = false
            }
        }
        .onTapGesture {
            windowState.isShowingCopyURLToast = false
        }
    }
}
