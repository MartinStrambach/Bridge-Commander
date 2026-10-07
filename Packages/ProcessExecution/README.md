# ProcessExecution

`ProcessRunner` shells out to external processes (`runGit(arguments:at:)` for git) and collects stdout/stderr through pipes read by `readabilityHandler`s, so a chatty process never fills a pipe buffer and blocks.

## Gotchas

- **Every exit path must release the pipes.** A launch that fails (`process.run()` throws, e.g. because the working directory of a just-deleted worktree is gone) never reaches the termination handler, and the never-launched `Process` plus the readability handlers keep both pipes open: six descriptors per failure. A GUI app gets launchd's soft limit of 256 descriptors, so a few dozen failures exhausted it. From then on `Pipe()` does not fail; it silently returns handles on fd 0, and every launch, in every repository, fails with "Failed to start process: … Bad file descriptor" until the app is restarted. The `catch` path therefore clears the termination and readability handlers and closes all four pipe ends. `ProcessRunnerTests.failedLaunchesDoNotLeakFileDescriptors` guards it.
- To inspect a running app's descriptors: `lsof -p $(pgrep -x BridgeCommander) | wc -l`.
