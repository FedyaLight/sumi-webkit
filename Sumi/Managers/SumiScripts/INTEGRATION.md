# SumiScripts Module - Integration Guide

This document describes how the native Sumi userscript runtime is wired into the BrowserServicesKit user-script pipeline.

## Overview

The runtime is owned by `SumiUserscriptsModule`, which is attached to `BrowserManager` but does not construct `SumiScriptsManager` until `SumiModuleRegistry.isEnabled(.userScripts)` is true and a userscript feature actually needs the manager. While disabled there is no manager, store watcher, installed-script adapter, pending install/update work, GM bridge, or BSK `UserScript` contribution for future normal-tab navigations.

Normal tabs do not mutate `WKUserContentController` directly. They build one `SumiNormalTabUserScripts` provider and install it through the Prompt 03 BrowserServicesKit `UserContentController`.

### Lifecycle

```
Tab setup / normal-tab navigation
  -> BrowserConfiguration.normalTabWebViewConfiguration(..., userScriptsProvider:)
  -> SumiNormalTabUserScripts
      -> DDG favicon UserScripts
      -> Tab core UserScripts
      -> ExtensionManager externally-connectable UserScript
      -> SumiUserscriptsModule enabled-only installed UserScript adapters
          -> SumiScriptsManager
          -> UserScriptInjector.makeUserScripts(...)
          -> SumiInstalledUserScriptAdapter / SumiInstalledUserStyleAdapter
          -> UserScriptGMBridge behind a BSK UserScriptMessageBroker
  -> BSK UserContentController installs WKUserScripts and weak broker handlers
```

Remote `.user.js` navigation is intercepted through `SumiUserscriptsModule`; disabled module state returns no interception and constructs no userscript runtime.

## SwiftData Note

`UserScriptEntity` and `UserScriptResourceEntity` are written from `UserScriptStore+SwiftData.swift` when a `ModelContext` is available. The filesystem remains the authoritative catalog; SwiftData exists for schema registration (`SumiStartupPersistence`) and a durable install index.

## Normal-Tab Registration

`Tab.normalTabUserScriptsProvider(for:)` constructs the provider before the `WKWebView` begins loading. `SumiTabScriptAttachmentNavigationResponder` refreshes provider contents at main-frame navigation start:

```swift
provider.replaceManagedUserScripts(normalTabManagedUserScripts(for: targetURL))
await controller.replaceUserScripts(with: provider)
```

That BSK replacement path removes only BSK-installed scripts/handlers and then installs the new provider output. Sumi does not run a document-idle `evaluateJavaScript` injection loop and does not use a production `removeAllUserScripts` preservation workaround for userscripts.

## Broker Boundaries

Each script or feature owns its own BSK `UserScriptMessageBroker` context:

| Context | Owner |
| --- | --- |
| `sumiGM_<script.uuid>` | Installed userscript GM bridge. |
| `sumiLinkInteraction_<tab.uuid>` | Link hover, command hover, and modified-click handling. |
| `sumiIdentity_<tab.uuid>` | Page identity request bridge. |
| `sumiExternallyConnectableRuntime` | WebExtension externally-connectable page bridge. |

Payload parsing stays local to the subfeature. Malformed payloads return no side effects, unknown methods are ignored by the broker, and handler lifetime is tied to the BSK user content controller.

## GM Compatibility

Sumi keeps GM APIs because installed userscripts rely on them. The native bridge is no longer a global script-message hot path:

- `UserScriptInjector` returns BSK `UserScript` adapters instead of mutating a controller.
- `SumiInstalledUserScriptAdapter` registers a per-script broker only when the script needs GM/native glue.
- `SumiGMSubfeature` routes allowed GM methods to `UserScriptGMBridge`.
- Network and download APIs remain native, but only through the typed `gm` broker boundary.

## WebKit Compatibility (`@sumi-compat` and Built-In `@require`)

Sumi ships optional compat preludes for userscripts that hit WebKit-specific media/audio edge cases. They are opt-in only.

- Declarative: add one or more lines to the metablock, for example `// @sumi-compat webkit-media`.
- As `@require`: `// @require sumi-internal://userscript-compat/webkit-media.js` resolves to the same bundled script without network access.

Bundled modules:

| Module id | Purpose |
| --- | --- |
| `webkit-media` | Replaces `AudioContext.prototype.suspend` with a resolved no-op for specific WebKit media userscript compatibility cases. |

## Verification Checklist

After integration, verify:

1. A `@run-at document-start` script is present in the provider before first navigation.
2. `@run-at document-end` and `@run-at document-idle` scripts are represented as `WKUserScript` injection times, not post-load eval loops.
3. GM APIs route through the per-script `sumiGM_<uuid>` broker.
4. Disabling SumiScripts stops returning installed-script adapters for future normal-tab navigations.
5. Editing a `.user.js` file reloads store state and affects the next provider replacement.
6. BSK controller cleanup removes script-message handlers when a WebView/configuration is released.
7. `scripts/check_userscript_hot_paths.sh` passes.
