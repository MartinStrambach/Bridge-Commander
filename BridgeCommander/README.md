# BridgeCommander (app target)

App entry point and the Sparkle updater. Project-wide conventions are in the root `CLAUDE.md`.

## Updates (Sparkle)

- Updates come from Sparkle (the app target's only direct package besides TCA). `BridgeCommanderApp` owns the `SPUStandardUpdaterController`; `CheckForUpdatesView` is the "Check for Updates…" app-menu item. The updater is started only in Release builds: a Debug build runs out of DerivedData, and installing an update there would replace the build being worked on
- Settings ▸ Updates (`UpdateSettingsView`) toggles automatic checks and automatic download/install, with a Check Now button. They read and write `SPUUpdater`'s own properties (`automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`), which Sparkle persists itself — the same preferences its second-launch prompt and the update dialog's checkbox set, so they are not mirrored in `SettingsReducer`. Both views observe them through `UpdaterViewModel` (KVO). The view lives in the app target and is handed to `SettingsView` as its `updates` content, keeping the Settings package free of a Sparkle dependency; that makes `SettingsView` generic, so its former static stored properties sit at file scope. The download toggle is disabled while `allowsAutomaticUpdates` is false (automatic checks off), and the whole section in Debug builds
- The feed is an `appcast.xml` attached to each GitHub release by `make publish` (`scripts/make-appcast.sh`; see RELEASE.md)
