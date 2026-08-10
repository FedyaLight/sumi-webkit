Type: grilling
Status: resolved
Blocked by: 04, 06, 09

# What resource and repaint budget must the Sidebar Page Media design satisfy?

## Question

Set measurable CPU, GPU, RAM, wakeup, main-thread, cache, observer, task, timer, and repaint acceptance criteria for disabled, enabled-idle, collapsed-playing, expanded-playing, multiple-session, hidden-window, and teardown states. Decide when progress text/slider may repaint and whether one shared on-demand clock is justified, using timestamp-plus-playback-rate derivation rather than per-card timers.

## Comments

- Disabled remains structurally zero-cost: no observers, timers, tasks, MediaRemote process/bridge, broad cache, or background work.
- Hidden and overflow cards must not retain favicon decode or progress repaint work merely because their sessions are playing.

## Answer

The implementation adds no timer, polling loop, display link, broad cache, MediaRemote observer, helper process, or continuous animation. Refresh is event-driven by existing audio, scene, selection, and lifecycle callbacks, with only the existing cancellable bounded debounce. Candidate construction keeps only live WebView residences and metadata is sampled only for playing, retained, or dismissed owners.

At most three SwiftUI cards and favicon readers are materialized per sidebar. Additional sessions are value snapshots only. Collapsed and hidden cards have no progress repaint because progress is intentionally absent. Disabling the feature cancels refresh work, publishes an empty snapshot, and releases retained page suspension.
