Type: grilling
Status: resolved
Blocked by: 04, 08

# Does any MediaRemote enrichment earn its cost and correlation risk?

## Question

After page-scoped WebKit capabilities are known, does an in-process, observation-only MediaRemote bridge add metadata or capability that the exact Page Media Session lacks? If so, define the minimum correlation proof, reset behavior, privacy boundary, memory bound, failure isolation, and UI degradation when another app or Sumi tab becomes global Now Playing. Otherwise decide to omit MediaRemote entirely.

## Comments

- MediaRemote can never own card lifecycle or issue commands.
- The preferred answer is omission unless a concrete user-visible capability survives strict correlation and measured resource cost.

## Answer

MediaRemote is omitted. It provides no target token that can prove correspondence with one exact Sumi WebView residence, so its metadata does not earn the correlation risk, private-framework dependency, process/memory cost, or reset complexity. The implementation uses WebKit only.
