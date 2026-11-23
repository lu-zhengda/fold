#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source script/package.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for file in script/*.sh; do bash -n "$file"; done
mkdir -p .build/verification
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
coverage=$(swift test --show-codecov-path)
test -s "$coverage"
cp "$coverage" .build/verification/coverage.json
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
app="$work/image/Fold.app"
build_bundle "$app"
codesign --force --sign - "$app"
create_image "$work/image" "$work/Fold.dmg"
script/verify-image.sh "$work/Fold.dmg" "$version"
if [[ ${1:-} == --launch ]]; then swift script/launch-smoke.swift "$app"; fi
