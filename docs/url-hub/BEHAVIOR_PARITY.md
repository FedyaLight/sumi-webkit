# URL Hub Behavior Parity

This document is the refactor contract for the URL hub. Refactor passes should
preserve these behaviors unless a product change explicitly updates this file.

## Entry Points

- The site controls button opens a native `NSPopover` anchored to the URL bar.
- Toggling the site controls button closes an already-open URL hub for the same
  window.
- Bookmark editor requests may open the same popover and route into the bookmark
  editor surface.
- Opening the permission indicator popover, zoom popover, or a permission prompt
  closes the URL hub.
- Changing the active tab closes the URL hub.

## Root Surface

- The root URL hub surface is the controls view.
- The header actions are Share, Reader Mode placeholder, Screenshot, and
  Bookmark/Edit Bookmark.
- The extension section appears only when enabled extensions or userscripts are
  available.
- Settings rows include extension controls and cookies/site data for normal web pages.
- Local pages show a local page row.
- Internal pages omit normal settings rows.

## Permissions

- Permission rows render inline in the root URL hub, not as a submenu.
- Rows are filtered to permissions the site used, requested, has a resolved
  policy for, changed through settings, or auto-detected.
- Row subtitles use compact values: On, Off, or Default.
- Clicking an editable permission row cycles Default/Ask -> Off -> On -> Off
  for supported rows.
- Context menus expose explicit policy choices and system settings only where the
  row supports them.
- Permission indicator icons in the URL bar are hidden while the URL hub is open.

## Footer

- The security footer keeps its text on one line when possible.
- The gear button opens Site Settings on primary click.
- The gear context menu exposes Site Settings, Clear Site Data, and Reset
  Permissions to Default.
- Clear Site Data routes to the site data details surface.

## Site Data Details

- The site data details surface loads data for the current site/profile.
- Deleting an entry asks for confirmation.
- Mutating site data policies refreshes the root URL hub summary.

## Validation

Run these after each URL hub refactor pass:

```sh
xcodebuild -scheme Sumi -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -only-testing:SumiTests/SumiURLHubPermissionsSubmenuTests \
  -only-testing:SumiTests/SumiPermissionURLHubIntegrationTests \
  -only-testing:SumiTests/SumiCurrentSitePermissionsViewModelTests \
  -only-testing:SumiTests/SumiPermissionIndicatorViewModelTests \
  -only-testing:SumiTests/SumiPermissionRuntimeControlIntegrationTests \
  test
```

For UI-risky changes, manually check:

- Open/close hub from the site controls button.
- Open hub on secure, insecure, local, and internal pages.
- Trigger autoplay and confirm the row persists across the registrable site.
- Toggle a permission row and confirm the URL bar permission indicator does not
  duplicate the same state while the hub is open.
- Open the gear context menu and each route.
