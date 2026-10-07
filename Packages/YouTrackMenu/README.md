# YouTrackMenu

YouTrack ticket menu (move to a reachable state).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `YouTrackButtonReducer` / `YouTrackButtonView` — moves a ticket to a different state
- Offers only the transitions YouTrack reports as reachable (`IssueDetails.stateTransitions`); the row supplies them, this package only applies the chosen one
