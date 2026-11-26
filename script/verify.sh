#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source script/package.sh
work=$(mktemp -d)
cleanup() {
    if [[ -f "$work/fold.pid" ]]; then
        local pid
        pid=$(cat "$work/fold.pid" 2>/dev/null || true)
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" 2>/dev/null || true
            local attempt
            for attempt in 1 2 3 4 5; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 0.2
            done
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
for file in script/*.sh; do bash -n "$file"; done
bash -n script/check-pr-standard.sh
swiftlint lint --strict --config .swiftlint.yml
swift script/launch-smoke.swift --self-test
script/test-plan-release.sh
mkdir -p .build/verification
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
coverage=$(swift test --show-codecov-path)
test -s "$coverage"
cp "$coverage" .build/verification/coverage.json
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
app="$work/image/Fold.app"
build_bundle "$app"
stamp_version "$app" "$version"
codesign --force --sign - "$app"
create_image "$work/image" "$work/Fold.dmg"
build=$(bundle_build_number "$version")
EXPECTED_BUILD=$build script/verify-image.sh "$work/Fold.dmg" "$version"
if [[ ${1:-} == --launch ]]; then
    export FOLD_SMOKE_PIDFILE="$work/fold.pid"
    swift script/launch-smoke.swift "$app" --check-history --library "$work/library"
fi
