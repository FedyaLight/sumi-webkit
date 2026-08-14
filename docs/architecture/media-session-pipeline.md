# Media session pipeline

WebKit owns playback, fullscreen, Picture in Picture, and the underlying media
session. Sumi adds one browser surface: a sidebar card for an already-live
background page.

## Ownership

- `SumiNativeNowPlayingController` reconciles eligible background residences,
  publishes card state, retains card-owned pause/mute intent, and routes explicit
  card actions.
- `SumiNativeNowPlayingBridge` is the narrow adapter to WebKit's native metadata,
  exact residence audio state, play, pause, mute, and Picture in Picture
  operations.
- `Tab.mediaRuntime` records event-driven native state used by suspension policy.
- `MediaControlsView` renders immutable card state and emits user intent.

Only regular, non-incognito tabs are candidates. The active foreground tab is
not represented by the sidebar card, and card identity is stable for the owner
Page Media Session (`tab + window + residence generation + WebView identity`).

Initial admission requires unmuted audible output from the exact live WebView
Residence. Native metadata and generic playback state decorate an admitted card
but never admit one. A card-originated pause or mute retains that exact Page
Media Session when audible output stops; an externally muted or silent page does
not create or retain a card.

## Command rules

Transport controls resolve the existing live WebView for the owner and send one
native Page Media Session command. Pause does not suspend the webpage, so its
own controls remain able to resume media. Transport commands do not select a
tab, change Space, focus a page, materialize a WebView, sleep, or retry. Failure
leaves browser selection and page lifecycle untouched. Clicking the card itself
is the separate, explicit command that activates the owner page. Page Activation
only changes
presentation: it never resumes a Retained Paused Session or a Dismissed Media
Session. Closing a card pauses its native media and suppresses the card until a
later audible playback epoch.

## Suspension and teardown

Suspension is vetoed by live native evidence: audible playback, Picture in
Picture, capture, or fullscreen. It does not depend on DOM media listeners,
metadata sampling, polling, or a recently-audible timer.

Moving a page between window residences preserves its WebKit-owned presentation.
Only destruction of the owner page closes native media presentations, and
physical cleanup proceeds from WebKit's completion callback.

## Do not reintroduce

- `MediaRemote`, `MPNowPlayingInfoCenter`, or Sumi-owned system now-playing state.
- JavaScript playback or Picture in Picture sensors.
- Touch Bar reconstruction and fullscreen selection choreography.
- View-layer owner election or fallback materialization from a media command.
