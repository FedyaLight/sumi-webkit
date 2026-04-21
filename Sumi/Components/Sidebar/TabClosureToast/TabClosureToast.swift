//
//  TabClosureToast.swift
//  Sumi
//
//  Created by Jonathan Caudill on 02/10/2025.
//

import SwiftUI

struct TabClosureToast: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ToastView {
            ToastContentWithSubtitle(
                icon: "arrow.counterclockwise",
                title: "\(browserManager.tabClosureToastCount) tab\(browserManager.tabClosureToastCount > 1 ? "s" : "") closed",
                subtitle: "Press ⌘Z to undo"
            )
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                browserManager.hideTabClosureToast()
            }
        }
        .onTapGesture {
            browserManager.hideTabClosureToast()
        }
    }
}
