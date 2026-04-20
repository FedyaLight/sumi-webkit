# Aura settings surface

Aura uses `aura://settings/` for secondary settings surfaces that do not belong
in the always-live native browser chrome.

## Scope

The first Aura-owned settings surface is a real settings IA, not a one-panel
utility surface.

It contains:

- `Theme`
- `Layout`
- `Spaces & Essentials`
- `Keyboard`
- `Import/Export`

## Placement

- this is a browser settings route, not a detached utility window
- the page is allowed to use WebUI + Mojo because it is not the primary browser
  shell
- native browser chrome remains in Helium views and Aura native hosts

## Rules

- the settings page must call canonical Aura services
- no settings UI may write JSON files directly
- no shell choreography or sidebar logic should live in the settings page
- the page must remain dormant when closed and never become a second shell
  runtime
- theme, layout, and customization settings must remain separate from restore
  state and session runtime

## V1 non-goals

- full browser settings IA redesign outside Aura-owned sections
- advanced shortcut rebinding UI
- onboarding and first-run flows outside customization import/export
- full profile cloning or sync surfaces
