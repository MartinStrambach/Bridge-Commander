#!/usr/bin/env bash
# Check that every package under Packages/ is set up like the others:
#   - listed in the Xcode project (the Packages group's file reference)
#   - its manifest ends with the loop that turns warnings into errors and
#     enables MemberImportVisibility for every target
#   - a TCA dependency enables the same deprecation traits as the app target
#   - every test target's folder exists (SwiftPM otherwise reports
#     "overlapping sources")
# Prints one line per problem and exits non-zero if there is any.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pbxproj=BridgeCommander.xcodeproj/project.pbxproj
problems=0

problem() {
  echo "$1"
  problems=$((problems + 1))
}

for manifest in Packages/*/Package.swift; do
  dir=$(dirname "$manifest")
  name=$(basename "$dir")

  grep -q "path = $dir;" "$pbxproj" ||
    problem "$name: not in the Xcode project. In Xcode, drag $dir into the Packages group (and add its product to the target's Frameworks if the app links it)"

  grep -q '\.treatAllWarnings(as: \.error)' "$manifest" &&
    grep -q '\.enableUpcomingFeature("MemberImportVisibility")' "$manifest" ||
    problem "$name: $manifest lacks the closing 'for target in package.targets' loop (treatAllWarnings + MemberImportVisibility); copy it from Packages/GitCore/Package.swift"

  if grep -q 'swift-composable-architecture.git' "$manifest"; then
    for trait in ComposableArchitecture2Deprecations ComposableArchitecture2DeprecationOverloads; do
      grep 'swift-composable-architecture.git' "$manifest" | grep -q "\"$trait\"" ||
        problem "$name: the TCA dependency does not enable the \"$trait\" trait the app enables, so swift build would accept code the app build rejects"
    done
  fi

  for test_target in $(perl -0777 -ne 'print "$1\n" while /\.testTarget\(\s*name:\s*"([^"]+)"/g' "$manifest"); do
    [[ -d "$dir/Tests/$test_target" ]] ||
      problem "$name: test target $test_target has no folder $dir/Tests/$test_target"
  done
done

if [[ $problems -eq 0 ]]; then
  echo "Packages: ok"
fi
[[ $problems -eq 0 ]]
