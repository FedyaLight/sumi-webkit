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
                if validationResult.requiresReplacementConfirmation,
                   let message = validationResult.userMessage {
                    Button(action: finishRecording) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Replace existing binding. \(message)")
                    .accessibilityLabel("Replace existing shortcut")
                } else if let message = validationResult.userMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11, weight: .semibold))
                        .help(message)
                        .accessibilityHidden(true)
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
        .background {
            if isRecording {
                ShortcutRecorderCaptureRepresentable(
                    onKeyDown: handleKeyDown,
                    onFlagsChanged: handleFlagsChanged,
                    onBlur: cancelRecording
                )
                .frame(width: 0, height: 0)
            }
        }
        .onDisappear {
            cancelRecording()
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
    }

    private func finishRecording() {
        guard let pendingCombination else {
            cancelRecording()
            return
        }

        isRecording = false
        let result = onCommit(pendingCombination)
        validationResult = result
        self.pendingCombination = nil
    }

    private func cancelRecording() {
        isRecording = false
        pendingCombination = nil
        activeModifiers = []
        validationResult = .valid
    }

    private func clearShortcut() {
        if onClear() {
            validationResult = .valid
        }
    }

    private func validate(_ combination: KeyCombination) {
        validationResult = onValidate(combination)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 0x35 { // Escape
            cancelRecording()
            return true
        }

        if event.keyCode == 0x33 { // Delete/Backspace
            _ = onClear()
            cancelRecording()
            return true
        }

        guard let combination = KeyCombination(from: event) else {
            return false
        }
        pendingCombination = combination
        validate(combination)
        if validationResult == .systemOwned {
            return false
        }
        if validationResult == .valid {
            finishRecording()
        }
        return true
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        activeModifiers = Modifiers(eventModifierFlags: event.modifierFlags)
        pendingCombination = nil
        validationResult = .valid
    }
}

private struct ShortcutRecorderCaptureRepresentable: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    let onFlagsChanged: (NSEvent) -> Void
    let onBlur: () -> Void

    func makeNSView(context _: Context) -> ShortcutRecorderCaptureView {
        let view = ShortcutRecorderCaptureView()
        update(view)
        DispatchQueue.main.async { [weak view] in
            view?.beginCaptureIfPossible()
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderCaptureView, context _: Context) {
        update(nsView)
        nsView.beginCaptureIfPossible()
    }

    static func dismantleNSView(
        _ nsView: ShortcutRecorderCaptureView,
        coordinator _: Void
    ) {
        nsView.endCaptureAndRestoreFocus()
    }

    private func update(_ view: ShortcutRecorderCaptureView) {
        view.onKeyDown = onKeyDown
        view.onFlagsChanged = onFlagsChanged
        view.onBlur = onBlur
    }
}

final class ShortcutRecorderCaptureView: NSView, KeyboardCommandCaptureResponder {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onFlagsChanged: ((NSEvent) -> Void)?
    var onBlur: (() -> Void)?

    private weak var focusReturnTarget: NSResponder?
    private var isEndingCapture = false
    private var windowResignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    func beginCaptureIfPossible() {
        guard !isEndingCapture,
              let window,
              window.firstResponder !== self else { return }
        focusReturnTarget = window.firstResponder
        _ = window.makeFirstResponder(self)
    }

    func endCaptureAndRestoreFocus() {
        isEndingCapture = true
        guard let window, window.firstResponder === self else { return }
        _ = window.makeFirstResponder(focusReturnTarget)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
        guard let window else {
            windowResignObserver = nil
            return
        }
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isEndingCapture else { return }
                self.onBlur?()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x30 { // Tab exits capture and follows the key loop.
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(nil)
            } else {
                window?.selectNextKeyView(nil)
            }
            if window?.firstResponder === self {
                _ = window?.makeFirstResponder(focusReturnTarget)
            }
            return
        }
        guard onKeyDown?(event) != true else { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        let primaryModifiers = event.modifierFlags.intersection([
            .command, .control, .option,
        ])
        if event.keyCode == 0x30, primaryModifiers.isEmpty {
            return false
        }
        return onKeyDown?(event) == true
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, !isEndingCapture {
            onBlur?()
        }
        return didResign
    }

    isolated deinit {
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
    }
}
