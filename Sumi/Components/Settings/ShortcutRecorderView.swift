//
//  ShortcutRecorderView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/30/2025.
//

import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    let keyCombination: KeyCombination?
    let onValidate: (KeyCombination) -> ShortcutValidationResult
    let onCommit: (KeyCombination) -> ShortcutValidationResult
    let onClear: () -> Bool

    @State private var isRecording = false
    @State private var pendingCombination: KeyCombination?
    @State private var validationResult: ShortcutValidationResult = .valid
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                HStack(spacing: 4) {
                    Image(systemName: isRecording ? "stop.fill" : "pencil")
                    Text(isRecording ? "Recording..." : (keyCombination?.displayString ?? "Not Set"))
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
                        .stroke(validationResult == .valid ? Color.clear : Color.red, lineWidth: 1)
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

            if let message = validationResult.userMessage {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .help(message)
            }

            Button("Clear") {
                clearShortcut()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(keyCombination == nil)
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
        validationResult = .valid
        removeKeyMonitor()
    }

    private func clearShortcut() {
        removeKeyMonitor()
        if onClear() {
            validationResult = .valid
        }
    }

    private func validate(_ combination: KeyCombination?) {
        guard let combination else {
            validationResult = .invalid
            return
        }
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
        if event.keyCode == 0x35 {
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
        pendingCombination = nil
        validationResult = Modifiers(eventModifierFlags: event.modifierFlags).isEmpty ? .valid : .invalid
    }
}
