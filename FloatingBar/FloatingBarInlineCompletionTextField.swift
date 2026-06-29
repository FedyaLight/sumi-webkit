//
//  FloatingBarInlineCompletionTextField.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct FloatingBarInlineCompletionTextField: NSViewRepresentable {
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

    func makeNSView(context: Context) -> FloatingBarInlineCompletionTextFieldView {
        let view = FloatingBarInlineCompletionTextFieldView()
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

    func updateNSView(_ nsView: FloatingBarInlineCompletionTextFieldView, context: Context) {
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

    private func update(_ nsView: FloatingBarInlineCompletionTextFieldView, context _: Context) {
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
        private var onBeginEditing: () -> Void = {}
        private var onTab: () -> Bool = { false }
        private var onReturn: () -> Void = {}
        private var onMoveSelection: (Int) -> Void = { _ in }
        private var onEscape: () -> Void = {}
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

final class FloatingBarInlineCompletionTextFieldView: NSView {
    let textField = FloatingBarInlineCompletionNSTextField()
    var wantsTextFocus = false {
        didSet {
            if !wantsTextFocus {
                focusGeneration &+= 1
            }
        }
    }
    private var handledFocusRequestID = 0
    private var focusGeneration: UInt64 = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTextFieldIfNeeded()
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
        guard wantsTextFocus else { return }

        focusGeneration &+= 1
        focusTextField(
            selectAll: selectAll,
            remainingRetries: 4,
            generation: focusGeneration
        )
    }

    private func focusTextField(
        selectAll: Bool,
        remainingRetries: Int,
        generation: UInt64
    ) {
        guard remainingRetries >= 0 else { return }
        guard wantsTextFocus,
              generation == focusGeneration
        else { return }

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
        if selectAll {
            textField.selectText(nil)
        }

        if window.firstResponder !== textField.currentEditor(),
           window.firstResponder !== textField {
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

final class FloatingBarInlineCompletionNSTextField: NSTextField {
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
