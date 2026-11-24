#!/usr/bin/env bash
# Sourced by the release builder and its credential-free CI check.
embed_sparkle() {
    local app=$1 artifact=$2
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources"
    ditto "$artifact/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$framework"
    cp "$artifact/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
    # Fold runs outside App Sandbox and uses Sparkle's in-process installer launcher.
    rm -rf "$framework/XPCServices" "$framework/Versions/Current/XPCServices"
    local signing=(--force --sign "${SIGNING_IDENTITY:--}")
    if [[ "${SIGNING_IDENTITY:--}" != - ]]; then signing+=(--options runtime --timestamp); fi
    codesign "${signing[@]}" "$framework/Versions/Current/Autoupdate"
    codesign "${signing[@]}" "$framework/Versions/Current/Updater.app"
    codesign "${signing[@]}" "$framework"
}

build_bundle() {
    local app=$1
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    local bins=() args=() arch
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
    embed_sparkle "$app" .build/release-arm64/artifacts/sparkle/Sparkle
    cp Resources/Info.plist "$app/Contents/"
    cp Resources/Fold.icns "$app/Contents/Resources/"
}

create_image() {
    local folder=$1 image=$2
    ln -s /Applications "$folder/Applications"
    hdiutil create -volname Fold -srcfolder "$folder" -fs HFS+ -format UDZO "$image"
}
