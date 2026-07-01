//
//  ShortcutRecorderView.swift
//  Sumi
//
//

import AppKit
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleRecording) {
                HStack(spacing: 4) {
                    if isRecording {
                        if let pendingCombination {
                            Text(KeyboardShortcutPresentation.displayString(for: pendingCombination))
                                .font(.system(.body, design: .default))
                                .fontWeight(.medium)
                        } else if !activeModifiers.isEmpty {
                            Text(activeModifiers.menuGlyphs)
                                .font(.system(.body, design: .default))
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        } else {
                            Text("Press keys...")
                                .font(.system(.body, design: .default))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if let keyCombination {
                            Text(KeyboardShortcutPresentation.displayString(for: keyCombination))
                                .font(.system(.body, design: .default))
                                .fontWeight(.medium)
                        } else {
                            Text("Record Shortcut")
                                .font(.system(.body, design: .default))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let message = validationResult.userMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 11, weight: .semibold))
                    .help(message)
                    .padding(.trailing, 6)
            } else if keyCombination != nil, !isRecording {
                Button(action: {
                    clearShortcut()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                .padding(.trailing, 6)
                .opacity(isHovering ? 1.0 : 0.0)
            }
        }
        .frame(width: 140, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isRecording ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isRecording ? 2 : 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
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
            let _ = onClear()
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
