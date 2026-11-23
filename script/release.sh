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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bins=()
for arch in arm64 x86_64; do
    args=(--scratch-path ".build/release-$arch" --configuration release --triple "$arch-apple-macosx14.0")
    swift build "${args[@]}" --product Fold
    bins+=("$(swift build "${args[@]}" --show-bin-path)/Fold")
done
lipo -create "${bins[@]}" -output "$app/Contents/MacOS/Fold"
strip -S "$app/Contents/MacOS/Fold"
for arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/Fold" -verify_arch "$arch"
done
cp Resources/Info.plist "$app/Contents/"
cp Resources/Fold.icns "$app/Contents/Resources/"
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
ln -s /Applications "$work/image/Applications"
image="Fold-$version.dmg"
hdiutil create -volname Fold -srcfolder "$work/image" -fs HFS+ -format UDZO "$work/$image"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$work/$image"
notarize "$work/$image" "$work/$image"
spctl --assess --type open --context context:primary-signature --verbose "$work/$image"
(cd "$work" && shasum -a 256 "$image" > checksums.txt)
mv "$work/$image" "$work/checksums.txt" "$out/"
