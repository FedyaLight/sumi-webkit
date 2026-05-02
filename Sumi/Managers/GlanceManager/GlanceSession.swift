//
//  GlanceSession.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import Foundation
import WebKit
import SwiftUI

@MainActor
class GlanceSession: ObservableObject, Identifiable {
    let id = UUID()
    let windowId: UUID
    let sourceProfileId: UUID?

    @Published var currentURL: URL
    @Published var title: String
    @Published var isLoading: Bool = true
    @Published var estimatedProgress: Double = 0

    init(
        targetURL: URL,
        windowId: UUID,
        sourceProfileId: UUID? = nil
    ) {
        self.windowId = windowId
        self.sourceProfileId = sourceProfileId
        self.currentURL = targetURL
        self.title = targetURL.absoluteString
    }

    func updateNavigationState(url: URL?, title: String?) {
        if let url { currentURL = url }
        if let title, !title.isEmpty { self.title = title }
    }

    func updateLoading(isLoading: Bool) {
        self.isLoading = isLoading
    }

    func updateProgress(_ progress: Double) {
        estimatedProgress = progress
    }
}
