//
//  ShortcutRecorderView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var keyCombination: KeyCombination
    @State private var isRecording = false
    @State private var pendingCombination: KeyCombination?
    @State private var hasConflict = false
    @State private var conflictAction: ShortcutAction? = nil
    @State private var eventMonitor: Any?

    let action: ShortcutAction
    let shortcutManager: KeyboardShortcutManager
    let onCommit: (KeyCombination) -> Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 4) {
                    Image(systemName: isRecording ? "stop.fill" : "pencil")
                    Text(isRecording ? "Recording..." : keyCombination.displayString)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.2) : Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hasConflict ? Color.red : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            if hasConflict, let conflictAction = conflictAction {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .help("Conflicts with \(conflictAction.displayName)")
            }

            Button("Clear") {
                clearShortcut()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(keyCombination.key.isEmpty && keyCombination.modifiers.isEmpty)
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func toggleRecording() {
        if isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        pendingCombination = nil
        hasConflict = false
        conflictAction = nil
        KeyboardShortcutManager.pushShortcutRecorderCaptureSession()
        setupKeyMonitor()
    }

    private func finishRecording() {
        guard let pendingCombination else {
            cancelRecording()
            return
        }

        isRecording = false
        removeKeyMonitor()
        if shortcutManager.isValidKeyCombination(pendingCombination),
           !hasConflict,
           onCommit(pendingCombination) {
            keyCombination = pendingCombination
        }
        self.pendingCombination = nil
    }

    private func cancelRecording() {
        isRecording = false
        pendingCombination = nil
        hasConflict = false
        conflictAction = nil
        removeKeyMonitor()
    }

    private func clearShortcut() {
        let emptyCombination = KeyCombination(key: "", modifiers: [])
        removeKeyMonitor()
        if onCommit(emptyCombination) {
            keyCombination = emptyCombination
        }
    }

    private func checkForConflicts(_ combination: KeyCombination?) {
        guard let combination, !combination.isEmpty else {
            hasConflict = false
            conflictAction = nil
            return
        }

        if let conflictingAction = shortcutManager.hasConflict(keyCombination: combination, excludingAction: action) {
            hasConflict = true
            conflictAction = conflictingAction
        } else {
            hasConflict = false
            conflictAction = nil
        }
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            guard isRecording else { return event }

            switch event.type {
            case .keyDown:
                handleKeyDown(event)
                return nil
            case .flagsChanged:
                handleFlagsChanged(event)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            KeyboardShortcutManager.popShortcutRecorderCaptureSession()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 0x35 {
            cancelRecording()
            return
        }

        guard let combination = KeyCombination(from: event) else { return }
        pendingCombination = combination
        checkForConflicts(combination)
        if shortcutManager.isValidKeyCombination(combination), !hasConflict {
            finishRecording()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        pendingCombination = KeyCombination(key: "", modifiers: Modifiers(eventModifierFlags: event.modifierFlags))
        checkForConflicts(nil)
    }
}
