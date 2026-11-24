#!/usr/bin/env bash
set -euo pipefail
image=${1:?Expected a disk image}
version=${2:?Expected the release version}
mode=${3:-}
mount=$(mktemp -d)
attached=false
cleanup() {
    if $attached; then hdiutil detach "$mount" || hdiutil detach "$mount" -force || exit 1; fi
    rmdir "$mount" || exit 1
}
trap cleanup EXIT
if [[ "$mode" == --distribution ]]; then
    codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "XY7H3QGJ2T" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$image"
    xcrun stapler validate "$image"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
fi
hdiutil attach "$image" -readonly -nobrowse -mountpoint "$mount"
attached=true
test "$(readlink "$mount/Applications")" = /Applications
"$(dirname "$0")/verify-bundle.sh" "$mount/Fold.app" "$version" "$mode"
plist="$mount/Fold.app/Contents/Info.plist"
if [[ "$mode" == --distribution ]] && (( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist") >= 3 )); then
    swift "$(dirname "$0")/verify-appcast.swift" "$image" "$plist"
fi
echo "PASS disk image layout and embedded app"
