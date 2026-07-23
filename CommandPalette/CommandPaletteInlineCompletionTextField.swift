//
//  CommandPaletteInlineCompletionTextField.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct CommandPaletteInlineCompletionTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let font: NSFont
    let primaryColor: NSColor
    let hidesCaret: Bool
    let movesInsertionPointToEnd: Bool
    let focusRequestID: Int
    let focusSelectAll: Bool
    let onBeginEditing: () -> Void
    let onTab: () -> Bool
    let onReturn: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let onDeleteAtEmptySiteSearch: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> CommandPaletteInlineCompletionTextFieldView {
        let view = CommandPaletteInlineCompletionTextFieldView()
        view.textField.delegate = context.coordinator
        view.textField.onBeginEditing = onBeginEditing
        context.coordinator.configure(
            onBeginEditing: onBeginEditing,
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(view, context: context)
        return view
    }

    func updateNSView(_ nsView: CommandPaletteInlineCompletionTextFieldView, context: Context) {
        nsView.textField.delegate = context.coordinator
        nsView.textField.onBeginEditing = onBeginEditing
        context.coordinator.configure(
            onBeginEditing: onBeginEditing,
            onTab: onTab,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection,
            onEscape: onEscape,
            onDeleteAtEmptySiteSearch: onDeleteAtEmptySiteSearch
        )
        update(nsView, context: context)
    }

    private func update(_ nsView: CommandPaletteInlineCompletionTextFieldView, context _: Context) {
        nsView.configure(
            text: text,
            font: font,
            primaryColor: primaryColor,
            hidesCaret: hidesCaret,
            movesInsertionPointToEnd: movesInsertionPointToEnd
        )

        nsView.wantsTextFocus = isFocused.wrappedValue
        nsView.handleFocusRequest(id: focusRequestID, selectAll: focusSelectAll)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var onBeginEditing: () -> Void = { /* No-op. */ }
        private var onTab: () -> Bool = { false }
        private var onReturn: () -> Void = { /* No-op. */ }
        private var onMoveSelection: (Int) -> Void = { _ in /* No-op. */ }
        private var onEscape: () -> Void = { /* No-op. */ }
        private var onDeleteAtEmptySiteSearch: () -> Bool = { false }

        init(text: Binding<String>) {
            _text = text
        }

        func configure(
            onBeginEditing: @escaping () -> Void,
            onTab: @escaping () -> Bool,
            onReturn: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void,
            onDeleteAtEmptySiteSearch: @escaping () -> Bool
        ) {
            self.onBeginEditing = onBeginEditing
            self.onTab = onTab
            self.onReturn = onReturn
            self.onMoveSelection = onMoveSelection
            self.onEscape = onEscape
            self.onDeleteAtEmptySiteSearch = onDeleteAtEmptySiteSearch
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            onBeginEditing()
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
                onBeginEditing()
                return false
            case #selector(NSResponder.moveLeft(_:)):
                onBeginEditing()
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

final class CommandPaletteInlineCompletionTextFieldView: NSView {
    let textField = CommandPaletteInlineCompletionNSTextField()
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
    private var focusGeneration: UInt64 = 0
    private var pendingFocusSelectAll: Bool?
    private var isObservingWindowKey = false

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
        primaryColor: NSColor,
        hidesCaret: Bool,
        movesInsertionPointToEnd: Bool
    ) {
        textField.font = font
        textField.textColor = primaryColor
        textField.normalTextColor = primaryColor
        textField.hidesCaret = hidesCaret

        textField.applyText(text, moveInsertionPointToEnd: movesInsertionPointToEnd)
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
        attemptPendingFocus()
    }

    private func attemptPendingFocus() {
        guard let selectAll = pendingFocusSelectAll else { return }

        guard let window else {
            // viewDidMoveToWindow re-attempts once attached.
            return
        }

        if isTextFieldFocused(in: window) {
            pendingFocusSelectAll = nil
            removeWindowKeyObserver()
            return
        }

        focusGeneration &+= 1
        focusTextField(
            selectAll: selectAll,
            remainingRetries: 8,
            generation: focusGeneration
        )
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
        attemptPendingFocus()
    }

    private func focusTextField(
        selectAll: Bool,
        remainingRetries: Int,
        generation: UInt64
    ) {
        guard generation == focusGeneration,
              pendingFocusSelectAll != nil
        else { return }

        guard remainingRetries >= 0 else {
            // Out of immediate retries — wait for the window to become key
            // (app launch, window restore) and try again then.
            installWindowKeyObserverIfNeeded()
            return
        }

        guard let window else {
            DispatchQueue.main.async { [weak self] in
                self?.focusTextField(
                    selectAll: selectAll,
                    remainingRetries: remainingRetries - 1,
                    generation: generation
                )
            }
            return
        }

        window.makeFirstResponder(textField)

        if isTextFieldFocused(in: window) {
            if selectAll {
                textField.selectText(nil)
            }
            pendingFocusSelectAll = nil
            removeWindowKeyObserver()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.focusTextField(
                    selectAll: selectAll,
                    remainingRetries: remainingRetries - 1,
                    generation: generation
                )
            }
        }
    }
}

final class CommandPaletteInlineCompletionNSTextField: NSTextField {
    var onBeginEditing: (() -> Void)?
    var normalTextColor: NSColor = .labelColor
    private let caretColor: NSColor = .systemBlue
    var hidesCaret: Bool = false {
        didSet {
            updateFieldEditorCaret()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onBeginEditing?()
        hidesCaret = false
        textColor = normalTextColor
        moveInsertionPointToEnd()
        super.mouseDown(with: event)
        updateFieldEditorCaret()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updateFieldEditorCaret()
        return result
    }

    private func updateFieldEditorCaret() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = hidesCaret ? .clear : caretColor
    }

    func applyText(_ text: String, moveInsertionPointToEnd: Bool) {
        if let editor = currentEditor() as? NSTextView {
            if editor.string != text {
                editor.string = text
            }
            stringValue = text
            if moveInsertionPointToEnd {
                let end = (text as NSString).length
                editor.setSelectedRange(NSRange(location: end, length: 0))
            }
            updateFieldEditorCaret()
            return
        }

        if stringValue != text {
            stringValue = text
        }
    }

    private func moveInsertionPointToEnd() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
    }
}
