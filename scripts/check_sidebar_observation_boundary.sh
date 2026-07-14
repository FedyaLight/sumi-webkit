#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

sidebar_root="SidebarChrome/Sidebar/SpacesSideBarView.swift"
sidebar_page="SidebarChrome/Sidebar/SpaceSidebarPageChrome.swift"
pinned_grid="Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift"
composition="Sumi/Managers/BrowserManager/BrowserWindowViewContextComposition.swift"
updates="Sumi/Components/Sidebar/SidebarUpdateStreams.swift"
live_folders="Sumi/LiveFolders/SumiLiveFolderManager.swift"
extension_surface="Sumi/Services/BrowserExtensionSurfaceStore.swift"
extension_actions="Sumi/Managers/ExtensionManager/SumiExtensionToolbarActionSurface.swift"
extension_site_access="Sumi/Managers/ExtensionManager/SumiExtensionToolbarSiteAccessOwner.swift"
extension_action_view="Sumi/Components/Extensions/ExtensionActionView.swift"
extension_action_target="Sumi/Managers/ExtensionManager/ExtensionActionPresentationTarget.swift"
url_bar_view="Sumi/Components/Sidebar/URLBarView.swift"
url_bar_hub="Sumi/Components/Sidebar/URLBarHubPopover.swift"
url_bar_shell="Sumi/Components/Sidebar/URLBarShellView.swift"
url_bar_trailing="Sumi/Components/Sidebar/URLBarTrailingActions.swift"
window_state="Sumi/Models/BrowserWindowState.swift"
exact_tab_admission="Sumi/Managers/BrowserManager/ExactTabResidenceAdmission.swift"
regular_tabs="Sumi/Managers/TabManager/RegularTabCollectionOwner.swift"
child_tab_rollback="Sumi/Managers/BrowserManager/WebKitChildTabRollback.swift"
child_window_rollback="Sumi/Managers/BrowserManager/WebKitChildWindowOpeningService.swift"
link_window_rollback="Sumi/Managers/BrowserManager/BrowserLinkWindowTransaction.swift"
link_private_receipt="Sumi/Managers/BrowserManager/BrowserLinkPrivateWindowRollbackReceipt.swift"
live_shortcuts="Sumi/Managers/TabManager/LiveShortcutTabRegistry.swift"
shortcut_materializer="Sumi/Managers/TabManager/ShortcutTabMaterializer.swift"
shortcut_bindings="Sumi/Managers/TabManager/ShortcutTabBindingSynchronizer.swift"
structural_lookup="Sumi/Managers/TabManager/TabStructuralLookupCoordinator.swift"
structure_scope="Sumi/BrowserRuntime/TabStructureEventBus.swift"
window_registry="Sumi/Managers/WindowRegistry/WindowRegistry.swift"
transition_snapshots="SidebarChrome/Sidebar/SpaceSidebarSnapshots.swift"
architecture_doc="docs/architecture.md"

if rg -n '\b(SidebarSpacePageModel|SidebarChromeModel|tabStructuralRevision)\b' \
  App Sumi SidebarChrome SumiTests; then
  echo "sidebar observation boundary: broad relay/revision owner regrew" >&2
  exit 1
fi

if rg -n 'let _ = .*Revision|objectWillChange' "$sidebar_root" "$pinned_grid"; then
  echo "sidebar observation boundary: discard-read or broad relay regrew in a rendering root" >&2
  exit 1
fi

if rg -n 'SidebarInventoryProjection|browserContext\.isTransitioningProfile\(\)' "$pinned_grid"; then
  echo "sidebar observation boundary: PinnedGrid must consume its typed page snapshot" >&2
  exit 1
fi

if rg -n 'structureChangedPublisher|AnyPublisher<Void, Never>' "$composition" "$updates"; then
  echo "sidebar observation boundary: global Void structural relay regrew" >&2
  exit 1
fi

if sed -n '/func contentChanges(for/,/^    }/p' "$live_folders" \
  | rg -n '\$sourcesByFolderId|\$itemsBySourceId|CombineLatest'; then
  echo "sidebar observation boundary: live-folder leaf remapped global dictionaries" >&2
  exit 1
fi

if sed -n '/func publishToolbarLayoutChanged/,/^    }/p' "$extension_surface" \
  | rg -n 'objectWillChange'; then
  echo "sidebar observation boundary: toolbar layout regrew broad objectWillChange invalidation" >&2
  exit 1
fi

if rg -n '@(ObservedObject|EnvironmentObject).*BrowserExtensionSurfaceStore|@ObservedObject var surfaceStore' \
  SidebarChrome Sumi/Components/Sidebar "$extension_action_view"; then
  echo "sidebar observation boundary: extension surface regained broad leaf observation" >&2
  exit 1
fi

if rg -n '\.environmentObject\([^)]*(extensionSurfaceStore|surfaceStore)' \
  App SidebarChrome Sumi/Components/Sidebar; then
  echo "sidebar observation boundary: broad extension store injection regrew" >&2
  exit 1
fi

if sed -n '/struct ExtensionActionButton: View/,/^}/p' "$extension_action_view" \
  | rg -n '@EnvironmentObject|actionStatesByExtensionID'; then
  echo "sidebar observation boundary: rendered extension button regained broad or extension-only state" >&2
  exit 1
fi

if rg -n '\.ephemeral(Tabs|Spaces)\.(append|remove)|\.ephemeral(Tabs|Spaces)\s*=' \
  App Sumi SidebarChrome --glob '!Sumi/Models/BrowserWindowState.swift'; then
  echo "sidebar observation boundary: private inventory bypassed its window authority" >&2
  exit 1
fi

if rg -n 'invalidate(TabStructuralRevision|ToolbarLayout)' \
  Sumi/Managers/ExtensionManager; then
  echo "sidebar observation boundary: extension lifetime/site access regained sidebar invalidation" >&2
  exit 1
fi

if sed -n '/func moveUnpinnedExtension/,/^    }/p' "$extension_actions" \
  | rg -n 'publishToolbarLayout'; then
  echo "sidebar observation boundary: URL Hub ordering invalidated toolbar layout" >&2
  exit 1
fi

rg -q 'tabStructureEventBus\.scopedStructureChangesPublisher' "$composition"
rg -q 'currentProfileAuthority\.\$isTransitioning' "$composition"
rg -q 'func pageChanges' "$updates"
rg -q 'snapshot = current()' "$updates"
rg -q 'folderContentChanged' "$live_folders"
rg -q 'func toolbarLayoutChanges' "$extension_surface"
rg -Fq 'toolbarLayoutChanges(for: profileId)' "$sidebar_page"
rg -q 'ephemeralInventoryAuthority\.spaceCatalogChanges' "$sidebar_root"
rg -q 'ephemeralInventoryAuthority\.tabInventoryChanges' "$sidebar_root"
rg -q '@ObservationIgnored' "$window_state"
rg -q 'elementsEqual' "$window_state"
rg -q 'struct ExactTabResidenceAdmission' "$exact_tab_admission"
rg -q 'containsIdentical' "$exact_tab_admission"
rg -q 'ifIdentical: tab' "$exact_tab_admission"
rg -Fq 'removeEphemeralTab(ifIdentical:' "$exact_tab_admission"
rg -q 'ifIdentical tab: Tab' "$regular_tabs"
rg -q 'ExactTabResidenceAdmission' "$child_tab_rollback"
rg -q 'ExactTabResidenceAdmission' "$child_window_rollback"
rg -q 'ExactTabResidenceAdmission' "$link_window_rollback"
if rg -n 'removeEphemeralTab\(id:|regularTabCollectionOwner\.remove\(' \
  "$child_tab_rollback" "$child_window_rollback" "$link_window_rollback"; then
  echo "sidebar observation boundary: rollback bypassed exact residence admission" >&2
  exit 1
fi
if rg -n 'removeAllEphemeralSpaces' "$link_window_rollback"; then
  echo "sidebar observation boundary: private link rollback regained broad space removal" >&2
  exit 1
fi
rg -q 'publishToolbarLayoutIfChanged' "$extension_actions"
rg -q 'BrowserExtensionToolbarDisplayRecord' "$extension_surface"
if sed -n '/struct BrowserExtensionToolbarDisplaySnapshot/,/^}/p' "$extension_surface" \
  | rg -n 'let .*InstalledExtension'; then
  echo "sidebar observation boundary: URL/action display snapshot retained broad installed records" >&2
  exit 1
fi
rg -q 'BrowserExtensionActionButtonModel' "$extension_surface"
rg -q 'actionPresentationChanges' "$extension_surface"
rg -q 'BrowserExtensionToolbarLayoutScope' "$extension_surface"
if rg -n 'publishToolbarLayoutChanged' "$extension_site_access"; then
  echo "sidebar observation boundary: site-access owner regained toolbar publication" >&2
  exit 1
fi

python3 - "$extension_surface" "$url_bar_view" "$url_bar_hub" \
  "$url_bar_shell" "$url_bar_trailing" "$updates" "$structure_scope" \
  "$live_shortcuts" "$shortcut_materializer" "$shortcut_bindings" \
  "$structural_lookup" "$extension_action_target" "$extension_action_view" \
  "$window_registry" "$link_window_rollback" "$link_private_receipt" \
  "$window_state" "$transition_snapshots" "$architecture_doc" <<'PY'
from pathlib import Path
import sys
import re

(
    extension_surface, url_bar_view, url_bar_hub, url_bar_shell,
    url_bar_trailing, updates, structure_scope, live_shortcuts,
    shortcut_materializer, shortcut_bindings, structural_lookup,
    extension_action_target, extension_action_view, window_registry,
    link_window_rollback, link_private_receipt, window_state,
    transition_snapshots, architecture_doc,
) = map(Path, sys.argv[1:])

def text(path):
    return path.read_text()

def require(value, needle, message):
    if needle not in value:
        raise SystemExit(f"sidebar observation boundary: {message}")

def forbid(value, needle, message):
    if needle in value:
        raise SystemExit(f"sidebar observation boundary: {message}")

def ordered(value, needles, message):
    cursor = -1
    for needle in needles:
        cursor = value.find(needle, cursor + 1)
        if cursor < 0:
            raise SystemExit(f"sidebar observation boundary: {message}")

# URL bar and the separately hosted AppKit Hub must enter the same demand
# protocol. Neither root may take an unsubscribed store snapshot.
roots = text(url_bar_view) + text(url_bar_hub)
for root in (text(url_bar_view), text(url_bar_hub)):
    forbid(root, "extensionSurfaceStore", "URL/Hub root regained direct extension-store access")
    forbid(root, ".toolbarDisplaySnapshot", "URL/Hub root regained unsubscribed display reads")
    require(root, "@StateObject", "URL/Hub root lost its mounted demand reader")
    require(root, "extensionDisplayModel.setDemanded(", "URL/Hub root does not enter/leave display demand")
require(roots, "profileID:", "URL/Hub demand lost exact profile scope")

surface = text(extension_surface)
model_init = surface.split("final class URLBarExtensionDisplayModel", 1)[1]
model_init = model_init.split("func setDemanded", 1)[0]
forbid(model_init, ".sink", "display model subscribes during construction")
install = surface.split("private func installSurfaceSubscriptionIfNeeded", 1)[1]
install = install.split("private func publish", 1)[0]
ordered(
    install,
    ["guard isDemanded, moduleEnabled", "surfaceCancellable = changes(profileID)", "publish(current(profileID))"],
    "display demand must gate, subscribe, then read",
)

# Live shortcut mutations affect the exact mounted window/page. Runtime-only
# lookup refreshes are not a valid sidebar publication.
runtime_mutators = "\n".join(map(text, (live_shortcuts, shortcut_materializer, shortcut_bindings)))
forbid(runtime_mutators, ".runtimeOnly", "live shortcut mutation is still filtered from mounted pages")
require(text(structural_lookup), "requestPublish(scope: entry.pageScope)", "live shortcut registry lacks exact page publication")
require(text(structure_scope), "struct TabStructurePageScope", "structure scope lacks physical window/page identity")
page_changes = text(updates).split("func pageChanges", 1)[1].split("var catalogChanges", 1)[0]
require(page_changes, "windowID: UUID", "pageChanges lost its window witness")
require(page_changes, "windowID: windowID", "pageChanges does not apply the window witness")

# An action target is physical-window authority, not a durable UUID hint.
target = text(extension_action_target)
for needle in (
    "let windowIdentifier: ObjectIdentifier",
    "let windowRegistrationReceipt: WindowRegistry.WindowRegistrationReceipt",
    "let window: BrowserWindowState",
    "window: BrowserWindowState",
    "manager.runtime.registeredWindow(",
    "hasUniqueResidence(",
    "currentPublication(",
    "exactContextIdentity",
):
    require(target, needle, "action target lost physical window/context/residence evidence")
view = text(extension_action_view)
require(view, "browserContext.windowState === target.window", "action delivery compares only window UUID")
require(view, "actionModel.snapshot(for: actionPresentationTarget)", "retarget can expose a stale interactive snapshot")
registry = text(window_registry)
for needle in (
    "struct WindowRegistrationReceipt",
    "private var registrationReceipts: [UUID: WindowRegistrationReceipt]",
    "nextRegistrationGeneration &+= 1",
    "func window(\n        ifCurrent receipt: WindowRegistrationReceipt",
):
    require(registry, needle, "window registry receipt is not exact per registration")

# Private rollback performs one all-or-nothing aggregate write. Inventory is
# published only after all window fields are final; the only later operation is
# an exact old-profile lease CAS.
discard = text(link_window_rollback).split("private func discard", 1)[1]
rollback = discard.split("case .ephemeral(let receipt):", 1)[1]
require(rollback, "receipt.commitRollbackAggregate(", "private rollback bypasses atomic aggregate commit")
rollback_tail = rollback.split("receipt.commitRollbackAggregate(", 1)[1]
if re.search(r"window\.(?:current|ephemeral|replace|remove|append)", rollback_tail):
    raise SystemExit("sidebar observation boundary: private rollback mutates window after aggregate publication")
ordered(
    rollback,
    ["receipt.commitRollbackAggregate(", "profiles.cancelEphemeralProfileCreation(", "expected: receipt.profile"],
    "private rollback tail is not exact old-lease CAS",
)
receipt = text(link_private_receipt)
require(receipt, "hasEphemeralProfileLease(", "private receipt does not prove exact profile lease")
atomic = text(window_state).split("func rollbackUnpublishedPrivateAggregate", 1)[1]
atomic = atomic.split("private func publishEphemeralTabInventoryChanged", 1)[0]
ordered(
    atomic,
    ["guard isIncognito", "defersEphemeralInventoryPublication = true", "ephemeralTabs.removeAll()", "ephemeralSpaces.removeAll()", "defersEphemeralInventoryPublication = false", "flushDeferredEphemeralInventoryPublication()", "return true"],
    "private aggregate mutation/publication order is not atomic",
)
forbid(
    atomic.split("defersEphemeralInventoryPublication = true", 1)[1],
    "guard ",
    "private aggregate has a failing tail after mutation begins",
)

# Transition snapshots cannot consume the extension-global action map; without
# exact target evidence they render static package icon and no dynamic badge.
transition = text(transition_snapshots)
forbid(transition, "actionStatesByExtensionID", "transition snapshot reads global action state")
transition_actions = transition.split("static func transitionExtensionActionsSnapshot", 1)[1]
transition_actions = transition_actions.split("private static func extensionIcon", 1)[0]
require(transition_actions, "badgeText: nil", "transition fallback retained dynamic badge")
require(transition_actions, "hasUnreadBadgeText: false", "transition fallback retained unread state")

doc = text(architecture_doc)
ordered(
    doc,
    ["scoped reader subscribes at activation", "before taking its fresh demand-time", "snapshot"],
    "architecture document states the wrong subscribe/read order",
)
PY

rg -q 'SidebarScopedSnapshotReader' "$sidebar_root"
rg -q 'contentChanges\(for: folder\.id\)' \
  Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift

echo "sidebar observation boundary passed"
