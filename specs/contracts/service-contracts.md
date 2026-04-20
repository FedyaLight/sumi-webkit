# Aura service contracts

## AuraShellCoordinator

- owns top-level native chrome composition
- owns the single interaction engine for drag, reorder, split, glance, and
  restore preview/commit flow
- owns the Aura split layout tree and the Zen-exact split command/menu policy
- owns address bar presentation and compact mode policy
- owns keyboard command semantics before delegating runtime verbs
- owns sidebar visual density policy and transient surface taxonomy
- owns shell restore order
- does not own browser runtime state
- consumes internal customization state plus a set of profile states, not one
  implicit active-profile blob

## AuraUrlbarActionService

- owns the canonical Aura URL bar action catalog
- owns prefixed action mode and adaptive learner semantics
- keeps learner state separate from customization import/export and window
  restore
- enforces `http(s)`-only copy-link availability
- matches actions against one typed context that includes URL, page-runtime, and
  selected-tab state instead of string-only heuristics
- provides the grounded Zen shell-command set as the default catalog
- does not own theme, media, or profile-routing policy

## AuraProfileRouter

- maps spaces to Chromium profiles
- keeps single-window routing semantics
- owns live essential profile attachment rules
- resolves launch profile choice for essentials and launchers
- does not own split layout, split menu semantics, or split hover controls

## AuraCustomizationService

- owns import, export, replace, and reset for Aura-owned customization
- owns the versioned customization bundle contract used by `aura://settings/`
- keeps import/export bundle logic separate from internal customization
  persistence
- owns saved custom theme colors and Aura-owned appearance preferences
- owns global dark-mode bias, acrylic-elements, and URL-bar visibility prefs
- owns preview and validation before destructive replace operations
- never writes JSON directly from settings UI handlers

## AuraThemeService

- owns workspace theme state and transitions
- separates workspace chrome theme from global site light/dark
- owns per-space theme customization inputs and transition interpolation
- owns global window scheme mode as a shell-level preference, not a per-space
  theme field
- owns theme editor preview/save/discard flow through the same runtime path used
  by live space switching
- builds one Zen-grounded chrome recipe for browser background, toolbar
  background, primary color, text contrast, and grain state
- must use the same recipe builder for live preview, saved commit, and
  space-switch transitions
- does not own profile routing or media visibility

## Aura split host policy

- Helium remains the only content-runtime host for split contents
- Aura owns Zen-exact split tree semantics, duplication rules, and hover header
  behavior on top of Helium's `MultiContentsView`
- split commands, context menus, hover header actions, and keyboard verbs must
  route through the same split owner

## AuraMediaSessionService

- adapts Helium media sessions into Aura sidebar card models
- never creates its own media detection path
- owns card ordering, audible-state projection, hover-only marquee rules,
  notes-animation eligibility, and per-playback-epoch dismissal policy
- does not own tab activation semantics outside media focus actions

## AuraSiteControlsService

- exposes current site security, autoplay, tracking, and site-data actions
- owns header, permission/settings, and footer state for the site-controls surface
