import AppKit
import SwiftUI

struct DownloadsToolbarButton: View {
    @ObservedObject var downloadManager: DownloadManager
    let popoverPresenter: DownloadsPopoverPresenter
    let action: () -> Void
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var settings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        DownloadsToolbarButtonContent(
            downloadManager: downloadManager,
            popoverPresenter: popoverPresenter,
            windowState: windowState,
            settings: settings,
            themeContext: themeContext,
            action: action
        )
    }
}

private struct DownloadsToolbarButtonContent: View {
    @ObservedObject var downloadManager: DownloadManager
    let popoverPresenter: DownloadsPopoverPresenter
    let windowState: BrowserWindowState
    let settings: SumiSettingsService
    let themeContext: ResolvedThemeContext
    let action: () -> Void

    @State private var displayedProgress: Double?
    @State private var hideRingTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(downloadManager.hasActiveDownloads ? "DownloadsActiveIcon" : "DownloadsIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)

                if let displayedProgress {
                    DownloadProgressRing(progress: displayedProgress, size: 22)
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
            .frame(width: 28, height: 28)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NavButtonStyle())
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .accessibilityIdentifier("downloads-button")
        .background(
            DownloadsPopoverAnchorView(
                popoverPresenter: popoverPresenter,
                downloadManager: downloadManager,
                windowState: windowState,
                settings: settings,
                themeContext: themeContext
            )
            .allowsHitTesting(false)
        )
        .sidebarAppKitPrimaryAction(action: action)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: displayedProgress != nil)
        .onAppear {
            updateDisplayedProgress(from: downloadManager.combinedProgressFraction)
        }
        .onChange(of: downloadManager.combinedProgressFraction) { _, progress in
            updateDisplayedProgress(from: progress)
        }
    }

    private func updateDisplayedProgress(from progress: Double?) {
        hideRingTask?.cancel()
        if let progress {
            displayedProgress = progress
            return
        }

        guard displayedProgress != nil else {
            displayedProgress = nil
            return
        }

        displayedProgress = 1
        hideRingTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run {
                if !Task.isCancelled {
                    displayedProgress = nil
                }
            }
        }
    }
}

private struct DownloadsPopoverAnchorView: NSViewRepresentable {
    let popoverPresenter: DownloadsPopoverPresenter
    let downloadManager: DownloadManager
    let windowState: BrowserWindowState
    let settings: SumiSettingsService
    let themeContext: ResolvedThemeContext

    func makeCoordinator() -> Coordinator {
        Coordinator(popoverPresenter: popoverPresenter, windowID: windowState.id)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.popoverPresenter = popoverPresenter
        context.coordinator.windowID = windowState.id
        register(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.popoverPresenter?.unregisterAnchor(
            nsView,
            windowID: coordinator.windowID
        )
    }

    private func register(_ view: NSView, coordinator: Coordinator) {
        coordinator.popoverPresenter = popoverPresenter
        coordinator.windowID = windowState.id
        popoverPresenter.registerAnchor(
            view,
            windowState: windowState,
            downloadManager: downloadManager,
            settings: settings,
            themeContext: themeContext
        )
    }

    final class Coordinator {
        weak var popoverPresenter: DownloadsPopoverPresenter?
        var windowID: UUID

        init(popoverPresenter: DownloadsPopoverPresenter, windowID: UUID) {
            self.popoverPresenter = popoverPresenter
            self.windowID = windowID
        }
    }
}
