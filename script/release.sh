#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    credentials=(--keychain-profile "$NOTARY_PROFILE")
else
    credentials=(--key "${ASC_KEY_PATH:?}" --key-id "${ASC_KEY_ID:?}" --issuer "${ASC_ISSUER_ID:?}")
fi
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
    appcast_key=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
else
    appcast_key=(--account local.fold.clipboard)
fi
version=${RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}
out="$PWD/dist"
mkdir -p "$out"
work=$(mktemp -d "$out/.release.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/image/Fold.app"
source script/package.sh
build_bundle "$app"
stamp_version "$app" "$version"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"

notarize() {
    local archive=$1 target=$2 attempt status id
    if ! xcrun notarytool submit "$archive" "${credentials[@]}" --wait --output-format json > "$work/result.json"; then
        echo "notarytool submit failed for $(basename "$archive")" >&2
    fi
    cat "$work/result.json"
    status=$(plutil -extract status raw "$work/result.json" 2>/dev/null || true)
    if [[ "$status" != Accepted ]]; then
        id=$(plutil -extract id raw "$work/result.json" 2>/dev/null || true)
        if [[ -n "$id" ]]; then xcrun notarytool log "$id" "${credentials[@]}" >&2 || true; fi
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
    "${appcast_key[@]}" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/lu-zhengda/fold/releases/download/v$version/" "$work/feed"
swift script/verify-appcast.swift "$work/feed/$image" "$app/Contents/Info.plist"
(cd "$work" && shasum -a 256 "$image" > checksums.txt)
mv "$work/feed/appcast.xml" "$work/$image" "$work/checksums.txt" "$out/"
