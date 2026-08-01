//
//  ShortcutRecorderView.swift
//  Sumi
//
//

import AppKit
import SumiDomain
import SwiftUI

struct ShortcutRecorderView: View {
    let keyCombination: KeyCombination?
    let onValidate: (KeyCombination) -> ShortcutValidationResult
    let onCommit: (KeyCombination) -> ShortcutValidationResult
    let onClear: () -> Bool

    @State private var isRecording = false
    @State private var pendingCombination: KeyCombination?
    @State private var activeModifiers: Modifiers = []
    @State private var validationResult: ShortcutValidationResult = .valid
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(recorderTitle)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 116)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isRecording ? "Press a key combination" : "Record shortcut")

            ZStack {
                if let message = validationResult.userMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11, weight: .semibold))
                        .help(message)
                } else if keyCombination != nil, !isRecording {
                    Button(action: clearShortcut) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Clear shortcut")
                    .accessibilityLabel("Clear shortcut")
                }
            }
            .frame(width: 18, height: 18)
        }
        .frame(width: 140, height: 24, alignment: .trailing)
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var recorderTitle: String {
        if isRecording {
            if let pendingCombination {
                return KeyboardShortcutPresentation.displayString(for: pendingCombination)
            }
            if !activeModifiers.isEmpty {
                return activeModifiers.menuGlyphs
            }
            return "Press keys…"
        }
        if let keyCombination {
            return KeyboardShortcutPresentation.displayString(for: keyCombination)
        }
        return "Record"
    }

    private func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        pendingCombination = nil
        activeModifiers = []
        validationResult = .valid
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
        let result = onCommit(pendingCombination)
        validationResult = result
        self.pendingCombination = nil
    }

    private func cancelRecording() {
        isRecording = false
        pendingCombination = nil
        activeModifiers = []
        validationResult = .valid
        removeKeyMonitor()
    }

    private func clearShortcut() {
        removeKeyMonitor()
        if onClear() {
            validationResult = .valid
        }
    }

    private func validate(_ combination: KeyCombination) {
        validationResult = onValidate(combination)
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
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
        if event.keyCode == 0x35 { // Escape
            cancelRecording()
            return
        }

        if event.keyCode == 0x33 { // Delete/Backspace
            _ = onClear()
            cancelRecording()
            return
        }

        guard let combination = KeyCombination(from: event) else { return }
        pendingCombination = combination
        validate(combination)
        if validationResult.allowsCommit {
            finishRecording()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        activeModifiers = Modifiers(eventModifierFlags: event.modifierFlags)
        pendingCombination = nil
        validationResult = .valid
    }
}
