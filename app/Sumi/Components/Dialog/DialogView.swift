//
//  DialogView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct DialogView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ZStack {
            if isPresentedInCurrentWindow,
               let dialog = browserManager.dialogManager.activeDialog {
                overlayBackground
                dialogContent(dialog)
                    .transition(dialogTransition)
                    .zIndex(1)
            }
        }
        // Require both: avoids a full-window hit target when `isVisible`/`activeDialog` are briefly out of sync,
        // and skips hit testing while the dialog subtree is empty (e.g. during transition teardown).
        .allowsHitTesting(isPresentedInCurrentWindow)
        .animation(.bouncy(duration: 0.2, extraBounce: -0.1), value: isPresentedInCurrentWindow)
    }

    @ViewBuilder
    private var overlayBackground: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture {
                browserManager.closeDialog()
            }
            .transition(.opacity)
    }

    @ViewBuilder
    private func dialogContent(_ dialog: AnyView) -> some View {
        HStack {
            Spacer()
            dialog
            Spacer()
        }
    }

    private var dialogTransition: AnyTransition {
        return .asymmetric(
            insertion: .offset(y: 24).combined(with: .opacity),
            removal: .offset(y: -18).combined(with: .opacity)
        )
    }

    private var isPresentedInCurrentWindow: Bool {
        browserManager.dialogManager.isPresented(in: windowState.window)
    }
}
