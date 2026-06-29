//
//  FloatingBarOutsideClickRouting.swift
//  Sumi
//
//

import AppKit

enum FloatingBarOutsideClickRouting {
    @MainActor
    static func monitorResult(
        for event: NSEvent,
        isFloatingBarVisible: Bool,
        cardView: NSView?,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        monitorResult(
            for: event,
            isFloatingBarVisible: isFloatingBarVisible,
            isEventInsideCard: isEventInsideCard(event, cardView: cardView),
            onOutsideClick: onOutsideClick
        )
    }

    static func monitorResult(
        for event: NSEvent,
        isFloatingBarVisible: Bool,
        isEventInsideCard: Bool,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        guard isFloatingBarVisible else { return event }
        guard !isEventInsideCard else { return event }

        onOutsideClick()
        return event
    }

    @MainActor
    static func isEventInsideCard(_ event: NSEvent, cardView: NSView?) -> Bool {
        guard let cardView,
              let eventWindow = event.window ?? NSApp.window(withWindowNumber: event.windowNumber),
              isLocationInsideCard(
                event.locationInWindow,
                eventWindow: eventWindow,
                cardView: cardView
              )
        else { return false }

        return true
    }

    @MainActor
    static func isLocationInsideCard(
        _ locationInWindow: NSPoint,
        eventWindow: NSWindow,
        cardView: NSView?
    ) -> Bool {
        guard let cardView,
              cardView.window === eventWindow
        else { return false }

        return isLocationInsideCard(locationInWindow, cardView: cardView)
    }

    @MainActor
    static func isLocationInsideCard(
        _ locationInWindow: NSPoint,
        cardView: NSView?
    ) -> Bool {
        guard let cardView else { return false }
        let localPoint = cardView.convert(locationInWindow, from: nil)
        return cardView.bounds.contains(localPoint)
    }
}
