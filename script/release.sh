#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARY_PROFILE")
else
    credentials=(--key "${ASC_KEY_PATH:?}" --key-id "${ASC_KEY_ID:?}" --issuer "${ASC_ISSUER_ID:?}")
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
out="$PWD/dist"
mkdir -p "$out"
work=$(mktemp -d "$out/.release.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/image/Fold.app"
source script/package.sh
build_bundle "$app"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"

notarize() {
    local archive=$1 target=$2 attempt
    xcrun notarytool submit "$archive" "${credentials[@]}" --wait --output-format json > "$work/result.json"
    cat "$work/result.json"
    if [[ "$(plutil -extract status raw "$work/result.json")" != Accepted ]]; then
        xcrun notarytool log "$(plutil -extract id raw "$work/result.json")" "${credentials[@]}" >&2
        return 1
    fi
    for attempt in 1 2 3 4 5; do
        if xcrun stapler staple "$target"; then break; fi
        sleep 10
    done
    xcrun stapler validate "$target"
}

ditto -c -k --keepParent "$app" "$work/Fold.zip"
notarize "$work/Fold.zip" "$app"
spctl --assess --type execute --verbose "$app"
image="Fold-$version.dmg"
create_image "$work/image" "$work/$image"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$work/$image"
notarize "$work/$image" "$work/$image"
spctl --assess --type open --context context:primary-signature --verbose "$work/$image"
mkdir "$work/feed"
ln "$work/$image" "$work/feed/$image"
.build/release-arm64/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account local.fold.clipboard --maximum-deltas 0 \
    --download-url-prefix "https://github.com/lu-zhengda/fold/releases/download/v$version/" "$work/feed"
swift script/verify-appcast.swift "$work/feed/$image" "$app/Contents/Info.plist"
(cd "$work" && shasum -a 256 "$image" > checksums.txt)
mv "$work/feed/appcast.xml" "$work/$image" "$work/checksums.txt" "$out/"
