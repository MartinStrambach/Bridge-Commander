# GitActionsMenu

Git actions menu (push/pull/fetch/stash/merge/checkout default/discard/abort).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- Force push is not a menu item. A push git refuses as non-fast-forward (`GitError.nonFastForwardRejection`, the usual outcome after a rebase or an amend) gets a "Force Push" button in its "Push Failed" alert (`GitActionsMenuReducer.pushFailedAlert`, `PushButtonReducer.forcePushTapped`), so it is offered only when it is needed and after git's own explanation, never one click away by accident. It force-pushes exactly the branch git refused (`GitRejectedPush`, kept in `forcePushOffer` while the alert is up) with lease (`GitPushHelper.Mode.forceWithLease`, GitCore README), not whatever HEAD is on by the time the button is pressed: a terminal tab can switch branch meanwhile. The terminal toolbar's Push button offers the same through its own alert (`RepositoryListReducer.pushFailedAlert`), with the same text (`PushButtonReducer.forcePushExplanation(for:)`). A `(fetch first)` rejection offers nothing (the remote has commits never fetched, and a lease push would refuse them anyway), and neither does a push refusing several refs (`push.default=matching`)
- The alert's extra button is `ScrollableAlertReducer`'s generic `actionTapped` (AppUI), so `GitActionsMenuReducer` takes it as the force push without checking which alert sent it. A second alert with an action has to be told apart there
