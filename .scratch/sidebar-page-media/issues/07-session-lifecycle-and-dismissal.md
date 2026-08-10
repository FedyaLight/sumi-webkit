Type: grilling
Status: resolved
Blocked by: 04, 05

# What exact events retain, replace, dismiss, or end a Page Media Session?

## Question

Define the event-driven state machine that distinguishes audible playback, explicit Mini Player pause, page-originated pause, natural end, transient silence, short notification sound, navigation/document replacement, WebView Residence replacement, suspension, unload, tab/window close, command failure, and user dismissal. Which exact identity revision prevents a Retained Paused Session or delayed async result from resurrecting a stale card?

## Comments

- Preserve the accepted rule: an acknowledged Mini Player pause retains the exact session; `×` pauses and dismisses it; a later new playback-start may create a fresh card.
- No grace timer may become lifecycle authority. A bounded delay may suppress notification pings only if cancellation and identity semantics are explicit.

## Answer

An exact residence is visible only while its sampled page state is playing or it is a Retained Paused Session created by an acknowledged Mini Player pause. Page-originated pause/end removes it. Mini Player pause retains only that residence; addressed resume releases retention. `×` removes the card immediately, pauses the page, and keeps a residence tombstone until an exact paused snapshot is observed; a later playback-start can then create a fresh card.

Refresh generations reject late metadata, while residence generation plus WebView object identity reject replacement documents. Activation hands a retained suspended page back to the page by clearing suspension; unload, feature disable, or loss of the exact residence clears retained and dismissed state. No grace timer or polling controls lifecycle.
