#!/usr/bin/env bash
# Run package tests, several packages at once, and print only failures and a
# one-line result per package. Full logs are kept per package.
#
# Usage:
#   scripts/test.sh                 packages changed since origin/main (committed,
#                                   staged, unstaged or untracked) and every
#                                   package that depends on them
#   scripts/test.sh all             every package
#   scripts/test.sh GitCore AppUI   just these
#
# TerminalFeature goes through `xcodebuild test`: `swift test` cannot compile
# SwiftTerm's Metal shader (see Packages/TerminalFeature/README.md).

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

log_dir="${TMPDIR:-/tmp}/bridge-commander-check"
mkdir -p "$log_dir"

diagnostic='^/[^:]+:[0-9]+:([0-9]+:)? (error|warning): '

# Runs one package's tests; called through xargs below.
if [[ "${1:-}" == "--one" ]]; then
  name="$2"
  log="$log_dir/test-$name.log"
  if [[ ! -d "Packages/$name/Tests" ]]; then
    echo "skip $name (no tests)"
    exit 0
  fi
  if [[ "$name" == "TerminalFeature" ]]; then
    (cd "Packages/$name" && xcodebuild test -scheme "$name" -destination 'platform=macOS' \
      -skipMacroValidation -skipPackagePluginValidation) >"$log" 2>&1
  else
    swift test --package-path "Packages/$name" >"$log" 2>&1
  fi
  status=$?
  # swift colours its diagnostics even into a file; strip the colours and links.
  perl -pi -e 's/\e\[[0-9;]*m//g; s/\e\]8;;.*?\e\\//g' "$log"
  summary=$(grep -E 'Test run with [0-9]+ tests?' "$log" | tail -1 | sed -E 's/^[^A-Za-z]*//')
  if [[ $status -eq 0 ]]; then
    echo "ok   $name${summary:+ — $summary}"
  else
    echo "FAIL $name${summary:+ — $summary} (log: $log)"
    # Compiler diagnostics, then Swift Testing / XCTest failures.
    { grep -E "$diagnostic" "$log" | sort -u
      grep -E '✘ Test .*(recorded an issue|failed)|error: -\[' "$log"
    } | head -40 | sed 's/^/     /'
    if ! grep -qE "$diagnostic|✘ Test" "$log"; then
      grep -v '^\s*$' "$log" | tail -15 | sed 's/^/     /'
    fi
  fi
  exit $status
fi

all_packages() {
  for manifest in Packages/*/Package.swift; do
    basename "$(dirname "$manifest")"
  done
}

changed_packages() {
  local base
  base=$(git merge-base origin/main HEAD 2>/dev/null || echo HEAD)
  {
    git diff --name-only "$base"
    git ls-files --others --exclude-standard
  } | sed -n -E 's#^Packages/([^/]+)/.*#\1#p' | sort -u
}

# Adds every package whose manifest depends on one already in the list, until
# nothing more is added.
with_dependents() {
  local selected="$1" added=1 name
  while [[ $added -eq 1 ]]; do
    added=0
    for name in $(all_packages); do
      case " $selected " in *" $name "*) continue ;; esac
      for dep in $selected; do
        if grep -q "path: \"../$dep\"" "Packages/$name/Package.swift"; then
          selected="$selected $name"
          added=1
          break
        fi
      done
    done
  done
  echo "$selected"
}

if [[ $# -eq 0 ]]; then
  changed=$(changed_packages | tr '\n' ' ')
  # Keep only names that are still packages (a removed package has no manifest).
  existing=""
  for name in $changed; do
    [[ -f "Packages/$name/Package.swift" ]] && existing="$existing $name"
  done
  if [[ -z "${existing// /}" ]]; then
    echo "No package changed since origin/main; nothing to test (scripts/test.sh all runs every package)."
    exit 0
  fi
  packages=$(with_dependents "$existing")
elif [[ "$1" == "all" ]]; then
  packages=$(all_packages | tr '\n' ' ')
else
  packages="$*"
fi

echo "Testing:$(echo " $packages" | tr -s ' ')"
# Four at a time: each package builds its own copy of the dependencies.
echo $packages | tr ' ' '\n' | grep -v '^$' | xargs -P 4 -I{} bash "${BASH_SOURCE[0]}" --one {}
