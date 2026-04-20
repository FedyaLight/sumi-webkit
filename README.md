<div align="center">
  <img width="230" height="230" src="./assets/icon.png" alt="Sumi Logo">
  <h1><b>Sumi</b></h1>
  <p>
    Sumi is a native macOS browser built on WebKit and SwiftUI—organized around vertical tabs,
    spaces, and profiles so browsing stays structured without heavy chrome.
    <br>
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.5+-blue" alt="macOS 15.5+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift"></a>
  <a href="https://www.gnu.org/licenses/gpl-3.0.html"><img src="https://img.shields.io/badge/License-GPL--3.0-green" alt="GPL-3.0"></a>
</p>

> Open `Sumi.xcodeproj` in this directory to build and run the Sumi app target (unit tests: `SumiTests`, UI tests: `SumiUITests`).

## Project status

This tree is primarily a **development and testbed** checkout: debugging is ongoing, behaviors and APIs may change, and not everything here is polished end-user packaging. Treat builds as **experimental** unless you are contributing or validating a specific change.

Design goals stay **simple, fast, and deliberately anti-bloat**—fewer nested surfaces than mainstream browsers, with keyboard-first shortcuts and a lightweight chrome footprint where we can keep it.

## Sidebar model: Essentials, folders, and launchers

Sumi’s sidebar is organized **per space** (workspace). Three ideas show up everywhere in code and UI:

- **Essentials** – the compact **pinned launcher grid** at the top of a space (capacity limits and drag targets live under `TabManager` / `PinnedGrid`; context menus literally call this region “Essentials”). Use it for the handful of sites or apps you want one click away.
- **Tab folders** – collapsible groups (`TabFolder`) that hold related tabs; drag-and-drop can move tabs between folders, the Essentials strip, and the general tab list.
- **Launcher projection** – for each space (and window), `TabManager` computes a **`SpaceLauncherProjection`**: which pins render at the top level, which belong inside a folder, and how those rows map onto the sidebar. Views such as `SpaceView` / `TabFolderView` consume that projection instead of hand-rolling ordering logic.

For deeper architectural notes (e.g. space theme swipe ownership), see [`docs/architecture/`](docs/architecture/).

## Acknowledgments

- **Zen Browser** informs the **workspace / vertical-tab mental model** and the overall “sidebar-first, low chrome” posture Sumi chases—especially how Essentials-style pinning coexists with dense tab lists.
- The codebase **started from the open-source Nook browser** but has been **heavily reworked** toward Sumi’s goals; treat today’s architecture and features as Sumi-first, not a drop-in Nook fork.
- A few **AppKit / WebKit helpers** (notably around **find-in-page** and related window chrome) **adapt code published by DuckDuckGo** for macOS under the **Apache License 2.0**—those files retain DDG copyright/SPDX headers. They are an implementation reference for specific subsystems, not an endorsement or full UI parity.

## Features  

- **Spaces and vertical tabs** – group work into spaces with a sidebar-first layout that keeps titles and drag-and-drop affordances close at hand.
- **Profiles** – isolate site data and extension surfaces per profile when you need separate contexts.
- **Extensions** – Chromium-oriented extension plumbing on top of WebKit, with UI for install, permissions, and debugging where supported.
- **Themes and window chrome** – coordinated light/dark styling, gradients, and sidebar chrome tuned for long reading sessions.
- **Productivity extras** – command palette, peek-style previews, split tabs, downloads, cookies/cache controls, and find-in-page tailored to the shell.

<p align="center">
  <img src="https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26" alt="Sumi screenshot">
</p>


## Getting Started  

### Build from Source

#### Prerequisites  
- macOS 15.5+
- [Xcode](https://developer.apple.com/xcode/) (to build from source)
```bash
# From the checked-out Sumi repository (this directory contains Sumi.xcodeproj)
open Sumi.xcodeproj
```

Some obj-c libraries may not play nice with Intel Macs, though there should technically be full interoperability. You can use any number of resources to debug. You will also need to delete a couple lines of code for *older* versions of macOS than Tahoe (26.0).

You’ll need to set your personal Development Team in Signing to build locally.

## Project Structure

Paths below are relative to the repository root (clone this repo and open `Sumi.xcodeproj` here).

```
.
├── Sumi.xcodeproj          # Xcode project for the Sumi target and tests
├── App/                     # Entry point (@main), window/content shell, commands
├── Sumi/                    # Primary app target (most SwiftUI and services)
│   ├── Managers/            # BrowserManager, TabManager, ExtensionManager, …
│   ├── Models/              # Tab, Space, Profile, BrowserConfig, …
│   ├── Components/          # SwiftUI UI (Sidebar, Browser, Settings, Peek, …)
│   ├── Services/            # Cross-cutting services (routing, diagnostics, …)
│   ├── Theme/               # Theming and chrome styling
│   ├── Utils/               # Helpers, WebKit wrappers, shaders, …
│   ├── Resources/           # Bundled scripts and related assets
│   └── …                    # Protocols, Extensions, Diagnostics, …
├── Navigation/              # Sidebar navigation helpers used by the shell
├── Onboarding/              # First-run / onboarding flows
├── CommandPalette/          # Command palette UI and accessories
├── UI/                      # Shared lightweight UI helpers
├── Settings/                # Settings-related helpers at target boundaries
├── SumiTests/               # Unit tests
├── SumiUITests/             # UI tests
├── assets/                  # README and marketing assets (e.g. icon)
├── docs/                    # Architecture and internal notes
├── scripts/                 # Development scripts
└── .github/                 # CI and GitHub metadata
```

Notable areas inside `Sumi/Components/` include **FindInPage** (in-page search) alongside Sidebar, Browser, Settings, Extensions, and related modules.

### Architecture Overview

The **`App/`** target owns the process entry point and wires high-level window and command surfaces; most browser behavior lives in the **`Sumi/`** module. Sumi follows a manager-oriented architecture where:

- **Managers** handle business logic and coordinate between subsystems.
- **Models** represent data and state (often using Swift’s `@Observable` macro).
- **Components** are SwiftUI views that update from model and manager state.
- **BrowserManager** remains the central coordinator connecting managers and UI.

---

### Licenses

Sumi is intended to be used under the **GNU General Public License v3.0**. See the [full license text](https://www.gnu.org/licenses/gpl-3.0.html).

Some files incorporate or adapt third-party code; those portions are identified in the relevant source headers (and in any README shipped with vendored subtrees, if present). Third-party licenses apply only to those portions.
