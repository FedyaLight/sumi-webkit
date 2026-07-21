//
//  SpaceHoverLabelSession.swift
//  Sumi
//
//  When the spaces-strip hover label is on screen.
//
//  The strip reports raw hover transitions; this owns the rest: the pointer rest
//  before the first label appears, the instant hand-off between icons once one
//  is up, and the suppression a drag or a teardown needs.
//

import Foundation

@MainActor
@Observable
final class SpaceHoverLabelSession {
    /// Pointer rest before the first label opens. Once a label is up, moving
    /// between icons swaps it with no further delay — leaving the strip is what
    /// arms the delay again.
    static let defaultOpenDelay: Duration = .milliseconds(400)

    /// The space the pointer is over. The strip also uses this to keep the
    /// hovered icon out of the compact-dot treatment and to scroll it into view.
    private(set) var hoveredSpaceID: UUID?

    /// The space whose label is actually drawn. It is stored separately from
    /// `hoveredSpaceID` so an item exit followed by the adjacent item's enter
    /// does not tear the plate down between AppKit hover events.
    private(set) var visibleSpaceID: UUID?

    private let openDelay: Duration
    private let handoffDelay: Duration
    /// Retained so tests can await the scheduled open instead of sleeping.
    @ObservationIgnored private(set) var openTask: Task<Void, Never>?
    /// A short grace period distinguishes crossing an item gap from resting in it.
    @ObservationIgnored private(set) var closeTask: Task<Void, Never>?

    init(
        openDelay: Duration = SpaceHoverLabelSession.defaultOpenDelay,
        handoffDelay: Duration = .milliseconds(80)
    ) {
        self.openDelay = openDelay
        self.handoffDelay = handoffDelay
    }

    isolated deinit {
        openTask?.cancel()
        closeTask?.cancel()
    }

    func hoverBegan(_ spaceID: UUID) {
        guard hoveredSpaceID != spaceID else { return }
        cancelPendingClose()
        hoveredSpaceID = spaceID
        if visibleSpaceID != nil {
            visibleSpaceID = spaceID
            return
        }
        scheduleOpen(for: spaceID)
    }

    /// The pointer left one icon but may enter its neighbour next. Keep the
    /// current plate alive briefly so adjacent AppKit exit/enter events are one
    /// visual hand-off rather than a removal followed by an insertion.
    func hoverEnded(_ spaceID: UUID) {
        guard hoveredSpaceID == spaceID else { return }
        cancelPendingOpen()
        hoveredSpaceID = nil
        guard visibleSpaceID == spaceID else { return }
        scheduleClose(for: spaceID)
    }

    /// Takes the label down and re-arms the delay: the pointer left the strip, a
    /// drag started, or the strip is going away.
    func suppress() {
        cancelPendingOpen()
        cancelPendingClose()
        hoveredSpaceID = nil
        visibleSpaceID = nil
    }

    private func scheduleOpen(for spaceID: UUID) {
        cancelPendingOpen()
        let delay = openDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, hoveredSpaceID == spaceID else { return }
            visibleSpaceID = spaceID
        }
    }

    private func scheduleClose(for spaceID: UUID) {
        cancelPendingClose()
        let delay = handoffDelay
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  !Task.isCancelled,
                  hoveredSpaceID == nil,
                  visibleSpaceID == spaceID
            else { return }
            visibleSpaceID = nil
        }
    }

    private func cancelPendingOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func cancelPendingClose() {
        closeTask?.cancel()
        closeTask = nil
    }
}
