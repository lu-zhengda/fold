#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-run}"
app="$PWD/dist/Fold.app"
bin="$app/Contents/MacOS/Fold"
swift build -c release --product Fold
product="$(swift build -c release --show-bin-path)/Fold"
pkill -f "^$bin$" 2>/dev/null || true
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$product" "$bin"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Fold.icns "$app/Contents/Resources/"
source script/package.sh
embed_sparkle "$app" .build/artifacts/sparkle/Sparkle
codesign --force --sign - "$app"
case "$mode" in
    run) open -n "$app" ;;
    --verify) open -n "$app"; sleep 1; pgrep -fx "$bin" >/dev/null ;;
    --debug) lldb -- "$bin" ;;
    --logs|--telemetry) open -n "$app"; /usr/bin/log stream --info --predicate 'process == "Fold"' ;;
    *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
