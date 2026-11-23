#!/usr/bin/env bash
set -euo pipefail
app=${1:?Expected the path to Fold.app}
version=${2:?Expected the release version}
plist="$app/Contents/Info.plist"
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
expect() {
    if [[ "$1" != "$2" ]]; then
        echo "Expected $3 to be '$2', got '$1'" >&2
        exit 1
    fi
}
plutil -lint "$plist"
expect "$(value CFBundleIdentifier)" local.fold.clipboard CFBundleIdentifier
expect "$(value CFBundleShortVersionString)" "$version" CFBundleShortVersionString
expect "$(value CFBundleExecutable)" Fold CFBundleExecutable
expect "$(value LSUIElement)" true LSUIElement
expect "$(value LSMinimumSystemVersion)" 14.0 LSMinimumSystemVersion
test -s "$app/Contents/Resources/$(value CFBundleIconFile)"
exe="$app/Contents/MacOS/Fold"
test -x "$exe"
for arch in arm64 x86_64; do
    lipo "$exe" -verify_arch "$arch"
    expect "$(xcrun vtool -arch "$arch" -show-build "$exe" | awk '$1 == "minos" {print $2}')" 14.0 "$arch deployment target"
done
codesign --verify --deep --strict --verbose=2 "$app"
if [[ ${3:-} == --distribution ]]; then
    # Bind the signed code to Fold's identifier and publisher, even on a Mac
    # that trusts other Developer ID certificates.
    codesign --verify --strict --all-architectures -R='anchor apple generic and identifier "local.fold.clipboard" and certificate leaf[subject.OU] = "XY7H3QGJ2T" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
echo "PASS Fold.app $version (arm64, x86_64)"
