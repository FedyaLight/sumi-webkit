# SumiScripts Module — Integration Guide

This document describes how the native `SumiScripts` runtime is wired into Sumi's browser lifecycle.

## Overview

The runtime is owned by `BrowserManager.sumiScriptsManager`. It is dormant while disabled: no store watcher, no active broker, no pending install/update work, and no new `WKUserScript` registrations.

### Lifecycle (data flow)

```
Tab (WKWebView setup / didFinish / close)
  → BrowserManager.sumiScriptsManager
      → UserScriptStore (scripts on disk, manifest.json; optional SwiftData mirror)
      → UserScriptInjector (WKUserScript + message handlers)
          → UserScriptGMBridge (+JSShim string, +Network XHR)
  Remote `.user.js` navigation → SumiScriptsRemoteInstall (URL rules, fetch preview, NSAlert)
```

---

## SwiftData note

`UserScriptEntity` / `UserScriptResourceEntity` are written from `UserScriptStore+SwiftData.swift` when a `ModelContext` is available. The authoritative catalog is still the filesystem; SwiftData exists for schema registration (`SumiStartupPersistence`) and a durable index of installs. No other modules query these entities today.

---

## 1. Tab+WebViewRuntime.swift — document-start injection

### Where
In the `setupWebView()` method, **after** the `WKWebViewConfiguration` is created and **before** the first navigation.

### What
Call `browserManager.sumiScriptsManager.installContentController()` to pre-install `document-start`, `document-body`, and `document-end` scripts into the `WKUserContentController`.

### Code
```swift
// In setupWebView(), after configuration is created:

// --- SumiScripts: Install userscripts into content controller ---
browserManager.sumiScriptsManager.installContentController(
    configuration.userContentController,
    for: self.url,
    webViewId: self.id,
    profileId: profileId,
    isEphemeral: isEphemeral
)
// --- End SumiScripts ---
```

### Why
`WKUserScript` with `.atDocumentStart` injection time **must** be registered on the `WKUserContentController` before the `WKWebView` begins navigation. This is the only way to guarantee `@run-at document-start` scripts execute before any page JavaScript.

---

## 2. Tab+NavigationDelegate.swift — document-idle injection

### Where
In `webView(_:didFinish:)`, alongside the existing injections (e.g., `injectLinkHoverJavaScript`).

### What
Call `browserManager.sumiScriptsManager.injectDocumentIdleScripts()` to inject `@run-at document-idle` scripts after the page has fully loaded.

### Code
```swift
// In webView(_:didFinish:), after existing injections:

// --- SumiScripts: Inject document-idle userscripts ---
if let currentURL = webView.url {
    browserManager.sumiScriptsManager.injectDocumentIdleScripts(for: webView, url: currentURL)
}
// --- End SumiScripts ---
```

### Why
`document-idle` scripts should only run after the page is fully loaded and the DOM is complete. Using `evaluateJavaScript` at `didFinish` mirrors the browser extension pattern of waiting for `readyState === "complete"`.

---

## 3. Tab.swift — cleanup on tab close (optional)

### Where
In `closeTab()`, before the WebView is released.

### What
Cleanup GM bridge message handlers to prevent memory leaks.

### Code
```swift
// In closeTab(), before performComprehensiveWebViewCleanup():

// --- SumiScripts: Cleanup userscript handlers ---
if let webView = _webView {
    browserManager.sumiScriptsManager.cleanupWebView(
        controller: webView.configuration.userContentController,
        webViewId: self.id
    )
}
// --- End SumiScripts ---
```

### Why
`WKScriptMessageHandler` references are retained by `WKUserContentController`. Without explicit cleanup, the GM bridge objects (and their associated `URLSession` tasks, `UserDefaults` references) would leak.

---

## 4. Sumi-owned UI presence

### Where
In the Sumi-owned userscript surfaces that display local tooling.

### What
Read `browserManager.sumiScriptsManager.extensionMetadata` for Sumi-owned userscript surfaces.

### Code
```swift
// In whatever method builds the SumiScripts list for the sidebar/popup:

// --- SumiScripts: Show as built-in userscript tooling ---
let sumiScriptsEntry = browserManager.sumiScriptsManager.extensionMetadata
extensions.append(sumiScriptsEntry)
// --- End SumiScripts ---
```

### Toggle behavior
```swift
// When user toggles SumiScripts on/off:
browserManager.sumiScriptsManager.isEnabled = newValue

// When disabled:
// - UserScriptStore is deallocated (FSEvents watcher stops)
// - UserScriptInjector is deallocated (all broker/bridge references released)
// - No WKUserScript is registered on any future navigation
// - totalScriptCount and activeScriptCount reset to 0
// - Memory: only the empty manager object remains
```

---

## WebKit compatibility (`@sumi-compat` and built-in `@require`)

Sumi ships optional **compat preludes** for userscripts that hit WebKit-specific media/audio edge cases. They are **opt-in** only (not applied to arbitrary scripts).

- **Declarative**: add one or more lines to the metablock, e.g. `// @sumi-compat webkit-media`. Modules are loaded from the app bundle and injected **after** the GM shim (if any) and **before** `@require` bodies and your script.
- **As `@require`**: `// @require sumi-internal://userscript-compat/webkit-media.js` resolves to the same bundled script (no network). Useful when you cannot edit upstream metadata beyond `@require`.

Bundled modules (expand over time):

| Module id | Purpose |
|-----------|---------|
| `webkit-media` | Replaces `AudioContext.prototype.suspend` with a resolved no-op so audio graph state stays consistent for some dubbing / translation userscript patterns in WebKit. Opt-in only. |

---

## Verification Checklist

After integration, verify:

1. **document-start**: A `@run-at document-start` script should execute before page JS
2. **document-end**: A `@run-at document-end` script should execute when DOM is ready
3. **document-idle**: A `@run-at document-idle` script should execute after `didFinish`
4. **GM APIs**: VOT script should be able to call `GM_xmlhttpRequest` to Yandex APIs
5. **Disable**: Toggling `isEnabled = false` should stop all injection immediately
6. **Re-enable**: Toggling `isEnabled = true` should reload scripts from disk
7. **Hot-reload**: Editing a `.user.js` file in the scripts directory should reload automatically
8. **Memory**: With 0 scripts and disabled, Instruments should show ~0 SumiScripts overhead
