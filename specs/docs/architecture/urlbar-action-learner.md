# URL Bar Action Learner

Aura keeps Zen-style command discovery and adaptive ranking, but treats the
learner as its own local store rather than mixing it into customization import,
window restore, or shell layout state.

## Ownership

- `AuraUrlbarActionService` owns the action catalog and ranking policy
- `AuraUrlbarLearnerStore` owns persistence for learner scores only
- `AuraShellCoordinator` owns address bar presentation, focus, and compact-mode
  choreography

## Action catalog

Aura freezes these action families from Zen as first-class URL bar results:

- global commands
- workspace switch actions
- theme appearance actions

The canonical source for this behavior is the Zen URL bar action provider and
global action catalog in:

- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/urlbar/ZenUBActionsProvider.sys.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/urlbar/ZenUBGlobalActions.sys.mjs`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/zen/urlbar/ZenUBResultsLearner.sys.mjs`

The grounded default Aura catalog now mirrors the live Zen command set for the
first native pass:

- `Toggle Compact Mode`
- `Open Theme Picker`
- `New Split View`
- `New Folder`
- `Copy Current URL`
- `Settings`
- `Open Private Window`
- `Open New Window`
- `New Blank Window`
- `Pin Tab`
- `Unpin Tab`
- `Next Space`
- `Previous Space`
- `Close Tab`
- `Reload Tab`
- `Reload Tab Without Cache`
- `Next Tab`
- `Previous Tab`
- `Capture Screenshot`
- `Toggle Tabs on Right`
- `Add to Essentials`
- `Remove from Essentials`
- `Find in Page`
- `Switch to Automatic Appearance`
- `Switch to Light Mode`
- `Switch to Dark Mode`
- `Print`

## Frozen rules

- keyboard-opened location bar uses the floating presentation
- click-opened location bar does not float
- floating open selects the full untrimmed value
- prefixed action mode shows all available actions
- prefixed action mode never trains the learner
- `Copy Current URL` is available only for `http` and `https` pages
- empty-space surfaces may still show global actions, but not actions that
  require a live page runtime
- ranking and gating run against one typed action context:
  - current URI
  - current display URL
  - current page title
  - empty-space state
  - live page runtime presence
  - selected-tab pin and Essential state
  - multi-space availability
- current URL actions receive an explicit score boost when the query matches
  the current URL or display URL
- live page actions receive an explicit context boost over weaker generic
  actions when a page-backed tab is active
- action matching uses both visible labels and grounded alias terms instead of
  label-only fuzzy matching

## Learner policy

- learner state is local adaptive history, not exportable customization
- learner scores are bounded to the Zen-style range `-5..5`
- executing an action increases its score
- showing but not using an action decreases its score
- neutral scores are dropped instead of being stored forever
- prioritized and deprioritized ordering is applied before normal text ranking

## Persistence boundary

- learner state persists separately from `AuraCustomizationBundle`
- learner state persists separately from `AuraWindowState`
- resetting customization does not implicitly wipe learner history unless the
  user asks for a broader settings reset
