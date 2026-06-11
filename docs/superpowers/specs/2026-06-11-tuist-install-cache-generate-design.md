# Tuist Install, Cache & Generate — Combined Action

## Summary

Add a new Tuist menu item "Install, Cache & Generate" that runs `tuist install`, `tuist cache`, and `tuist generate` sequentially in one operation. If any step fails, the sequence stops and reports the error.

## Changes

### `TuistCommandHelper.swift` (`ToolsIntegration`)

Add a new case to `TuistAction`:

```swift
case installCacheAndGenerate(TuistCacheType)
```

`commandString` for this case is unused (the reducer calls `runCommand` three times individually), so it can return an empty string or a descriptive placeholder.

### `TuistButtonReducer.swift` (`RepositoryFeature`)

- Add `case installCacheAndGenerateTapped` to `Action`.
- Handler sets `state.runningAction = .installCacheAndGenerate(cacheType)` and launches a `.run` effect that:
  1. Calls `TuistCommandHelper.runCommand(.install, ...)` — on failure, sends `actionCompleted(.installCacheAndGenerate(cacheType), .failure(error))` and returns.
  2. Calls `TuistCommandHelper.runCommand(.cache(cacheType), ...)` — on failure, same.
  3. Calls `TuistCommandHelper.runCommand(.generate, ...)` — sends `actionCompleted` with the result.
- Error title in `actionCompleted`: `"Tuist Install, Cache & Generate Failed"`.

### `TuistButtonView.swift` (`RepositoryFeature`)

- Add menu button (after Cache, before Edit):
  - Label: `"Install, Cache & Generate"`, systemImage: `"wand.and.stars"`
  - Sends `.installCacheAndGenerateTapped`
- `progressText`: `"Installing, Caching & Generating..."`
- `progressHelpText`: `"Running install, cache and generate..."`

## Non-Goals

- No sub-step progress tracking (shows a single static progress label for the whole sequence).
- No new settings or configuration.
