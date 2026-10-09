#!/usr/bin/env bash
# Build the app (Debug) and print only what matters: each compiler error or
# warning once, and the result. The full log is kept for anything else.
#
# Usage: scripts/build.sh [extra xcodebuild arguments...]

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

log_dir="${TMPDIR:-/tmp}/bridge-commander-check"
mkdir -p "$log_dir"
log="$log_dir/app-build.log"

# -skipMacroValidation / -skipPackagePluginValidation: a command-line build cannot
# answer Xcode's "Trust & Enable" prompt for the TCA/Dependencies macros or
# SwiftTerm's build plugin.
xcodebuild \
  -project BridgeCommander.xcodeproj \
  -scheme BridgeCommander \
  -configuration Debug \
  -destination 'platform=macOS' \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  "$@" \
  build >"$log" 2>&1
status=$?
# swift colours its diagnostics even into a file; strip the colours and links.
perl -pi -e 's/\e\[[0-9;]*m//g; s/\e\]8;;.*?\e\\//g' "$log"

# Compiler diagnostics only: "/path/File.swift:12:5: error: …". Matching on the
# path prefix keeps out build-plugin descriptions and linkd noise that merely
# contain "error".
grep -E '^/[^:]+:[0-9]+:([0-9]+:)? (error|warning): ' "$log" | sort -u
grep -E '^\*\* BUILD (SUCCEEDED|FAILED) \*\*' "$log" | tail -1

if [[ $status -ne 0 ]] && ! grep -qE '^/[^:]+:[0-9]+:([0-9]+:)? error: ' "$log"; then
  # Failed without a compiler error (package resolution, signing, macro trust):
  # show the end of the log, where xcodebuild says why.
  echo "--- last lines of $log"
  grep -v '^\s*$' "$log" | tail -25
fi

echo "Full log: $log"
exit $status
