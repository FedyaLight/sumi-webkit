import AppKit

/// Owns the AppKit lifecycle required to turn a focus request into an active
/// field editor, even when the request arrives before the view is attached to
/// a key window.
@MainActor
class ChromeTextFieldFocusHostView: NSView {
    let textField: NSTextField

    var wantsTextFocus = false {
        didSet {
            guard wantsTextFocus, wantsTextFocus != oldValue else { return }
            focusTextFieldIfNeeded()
            attemptPendingFocus()
        }
    }

    private var handledFocusRequestID: UInt?
    private var pendingFocusSelectAll: Bool?
    private var isObservingWindowKey = false
    private var hasScheduledAttachedRetry = false

    init(textField: NSTextField) {
        self.textField = textField
        super.init(frame: .zero)

        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        textField.intrinsicContentSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowKeyObserver()
        focusTextFieldIfNeeded()
        attemptPendingFocus()
    }

    func requestFocus(id: UInt, selectAll: Bool) {
        guard id != handledFocusRequestID else { return }
        handledFocusRequestID = id
        pendingFocusSelectAll = selectAll
        hasScheduledAttachedRetry = false
        attemptPendingFocus()
    }

    func cancelPendingFocus() {
        pendingFocusSelectAll = nil
        hasScheduledAttachedRetry = false
        removeWindowKeyObserver()
    }

    var ownsTextFocus: Bool {
        guard let window else { return false }
        return window.firstResponder === textField
            || (textField.currentEditor() != nil
                && window.firstResponder === textField.currentEditor())
    }

    private func focusTextFieldIfNeeded() {
        guard wantsTextFocus, let window, !ownsTextFocus else { return }
        window.makeFirstResponder(textField)
    }

    private func attemptPendingFocus() {
        guard let selectAll = pendingFocusSelectAll else { return }
        guard let window else {
            // viewDidMoveToWindow resumes the request after attachment.
            return
        }
        guard window.isKeyWindow else {
            installWindowKeyObserverIfNeeded()
            return
        }

        if !ownsTextFocus {
            window.makeFirstResponder(textField)
        }
        applySelection(selectAll: selectAll)

        if ownsTextFocus {
            pendingFocusSelectAll = nil
            removeWindowKeyObserver()
        } else {
            scheduleAttachedFocusRetryIfNeeded()
        }
    }

    private func applySelection(selectAll: Bool) {
        textField.selectText(nil)
        guard !selectAll,
              let editor = textField.currentEditor() as? NSTextView else {
            return
        }
        let end = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
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
