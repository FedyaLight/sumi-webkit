//
//  CommandPaletteTextField.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct CommandPaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let font: NSFont
    let primaryColor: NSColor
    let focusRequestID: Int
    let focusSelectAll: Bool
    let onTab: () -> Bool
    let onReturn: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let onDeleteAtEmptySiteSearch: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> CommandPaletteTextFieldView {
        let view = CommandPaletteTextFieldView()
        view.textField.delegate = context.coordinator
        context.coordinator.configure(
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(view, context: context)
        return view
    }

    func updateNSView(_ nsView: CommandPaletteTextFieldView, context: Context) {
        nsView.textField.delegate = context.coordinator
        context.coordinator.configure(
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(nsView, context: context)
    }

    private func update(_ nsView: CommandPaletteTextFieldView, context _: Context) {
        nsView.configure(
            text: text,
            font: font,
            primaryColor: primaryColor
        )

        nsView.wantsTextFocus = isFocused.wrappedValue
        nsView.handleFocusRequest(id: focusRequestID, selectAll: focusSelectAll)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var onTab: () -> Bool = { false }
        private var onReturn: () -> Void = { /* No-op. */ }
        private var onMoveSelection: (Int) -> Void = { _ in /* No-op. */ }
        private var onEscape: () -> Void = { /* No-op. */ }
        private var onDeleteAtEmptySiteSearch: () -> Bool = { false }

        init(text: Binding<String>) {
            _text = text
        }

        func configure(
            onTab: @escaping () -> Bool,
            onReturn: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void,
            onDeleteAtEmptySiteSearch: @escaping () -> Bool
        ) {
            self.onTab = onTab
            self.onReturn = onReturn
            self.onMoveSelection = onMoveSelection
            self.onEscape = onEscape
            self.onDeleteAtEmptySiteSearch = onDeleteAtEmptySiteSearch
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveSelection(1)
                return true
            case #selector(NSResponder.moveRight(_:)):
                return false
            case #selector(NSResponder.moveLeft(_:)):
                return false
            case #selector(NSResponder.insertTab(_:)):
                return onTab()
            case #selector(NSResponder.insertNewline(_:)):
                onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            case #selector(NSResponder.deleteBackward(_:)),
                 #selector(NSResponder.deleteForward(_:)):
                return onDeleteAtEmptySiteSearch()
            default:
                return false
            }
        }
    }
}

final class CommandPaletteTextFieldView: NSView {
    let textField = CommandPaletteNSTextField()
    // Focus-maintenance hint only. Explicit focus requests (handleFocusRequest)
    // are authoritative and must not be gated on this: the SwiftUI FocusState
    // backing it has no .focused() anchor, so it can stay false forever.
    var wantsTextFocus = false {
        didSet {
            guard wantsTextFocus, wantsTextFocus != oldValue else { return }
            attemptPendingFocus()
        }
    }
    private var handledFocusRequestID = 0
    private var pendingFocusSelectAll: Bool?
    private var isObservingWindowKey = false
    private var hasScheduledAttachedRetry = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowKeyObserver()
        focusTextFieldIfNeeded()
        attemptPendingFocus()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.setAccessibilityIdentifier("command-palette-input")
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    func configure(
        text: String,
        font: NSFont,
        primaryColor: NSColor
    ) {
        textField.font = font
        textField.textColor = primaryColor
        textField.applyText(text)
    }

    func focusTextFieldIfNeeded() {
        guard wantsTextFocus, let window else { return }
        if window.firstResponder !== textField,
           window.firstResponder !== textField.currentEditor() {
            window.makeFirstResponder(textField)
        }
    }

    func handleFocusRequest(id: Int, selectAll: Bool) {
        guard id != handledFocusRequestID else { return }
        handledFocusRequestID = id

        // Persist the intent until focus actually lands: at launch the view may
        // not be in a window yet, and the window may not be key yet.
        pendingFocusSelectAll = selectAll
        hasScheduledAttachedRetry = false
        attemptPendingFocus()
    }

    private func attemptPendingFocus() {
        guard let selectAll = pendingFocusSelectAll else { return }

        guard let window else {
            // viewDidMoveToWindow re-attempts once attached.
            return
        }

        guard window.isKeyWindow else {
            installWindowKeyObserverIfNeeded()
            return
        }

        if isTextFieldFocused(in: window) {
            pendingFocusSelectAll = nil
            removeWindowKeyObserver()
            return
        }

        window.makeFirstResponder(textField)
        textField.beginEditing(selectAll: selectAll)

        if isTextFieldFocused(in: window) {
            pendingFocusSelectAll = nil
            removeWindowKeyObserver()
        } else {
            scheduleAttachedFocusRetryIfNeeded()
        }
    }

    private func isTextFieldFocused(in window: NSWindow) -> Bool {
        window.firstResponder === textField
            || (textField.currentEditor() != nil && window.firstResponder === textField.currentEditor())
    }

    private func installWindowKeyObserverIfNeeded() {
        guard !isObservingWindowKey, let window else { return }
        isObservingWindowKey = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    private func removeWindowKeyObserver() {
        guard isObservingWindowKey else { return }
        isObservingWindowKey = false
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_: Notification) {
        hasScheduledAttachedRetry = false
        attemptPendingFocus()
    }

    private func scheduleAttachedFocusRetryIfNeeded() {
        guard !hasScheduledAttachedRetry else { return }
        hasScheduledAttachedRetry = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attemptPendingFocus()
        }
    }
}

final class CommandPaletteNSTextField: NSTextField {
    func applyText(_ text: String) {
        if let editor = currentEditor() as? NSTextView {
            if editor.string != text {
                editor.string = text
            }
            stringValue = text
            return
        }

        if stringValue != text {
            stringValue = text
        }
    }

    func beginEditing(selectAll: Bool) {
        selectText(nil)
        guard !selectAll else { return }
        moveInsertionPointToEnd()
    }

    private func moveInsertionPointToEnd() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
    }
}
