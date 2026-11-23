#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo=lu-zhengda/fold
cask=lu-zhengda/tap/fold
install=false
if [[ ${1:-} == --install-cask ]]; then install=true; shift; fi
if [[ $# -gt 1 || ( $# == 1 && ! $1 =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ) ]]; then
    echo "Usage: $0 [--install-cask] [vMAJOR.MINOR.PATCH]" >&2
    exit 2
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
release_args=(--repo "$repo" --json tagName,isDraft,isPrerelease)
if [[ $# == 1 ]]; then release_args+=("v${1#v}"); fi
gh release view "${release_args[@]}" > "$work/release.json"
tag=$(jq -er 'select(.isDraft == false and .isPrerelease == false) | .tagName' "$work/release.json")
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
version=${tag#v}
image="Fold-$version.dmg"
gh release download "$tag" --repo "$repo" --dir "$work" --pattern "$image" --pattern checksums.txt
# Compare the digest for this exact file; never interpret manifest paths as commands or inputs.
digest=$(shasum -a 256 "$work/$image" | cut -d' ' -f1)
grep -Fx "$digest  $image" "$work/checksums.txt"
echo "PASS published $tag download and SHA-256"
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");FoldVerification;$(uuidgen)" "$work/$image"
script/verify-image.sh "$work/$image" "$version" --distribution

if $install; then
    # For disposable runners only. Keep the user's trust configuration separate.
    export XDG_CONFIG_HOME="$work/config" HOMEBREW_NO_AUTO_UPDATE=1
    brew tap lu-zhengda/tap
    if brew command trust >/dev/null 2>&1; then brew trust --cask "$cask"; fi
    brew info --json=v2 --cask "$cask" > "$work/cask.json"
    jq -e --arg v "$version" --arg sha "$digest" \
        --arg url "https://github.com/$repo/releases/download/$tag/$image" \
        '.casks[0] | .version == $v and .sha256 == $sha and .url == $url
         and ([.artifacts[] | del(.zap) | select(length > 0) | keys[] | select(. != "target")] == ["app"])
         and any(.artifacts[]; .app == ["Fold.app"])' "$work/cask.json"
    if [[ -n "$(brew list --cask --versions fold)" || -e /Applications/Fold.app ]]; then
        echo "A clean runner with no existing Fold installation is required for --install-cask." >&2
        exit 1
    fi
    brew install --cask --appdir=/Applications "$cask"
    brew list --cask --versions fold | grep -Fx "fold $version"
    script/verify-bundle.sh /Applications/Fold.app "$version" --distribution
    swift script/launch-smoke.swift /Applications/Fold.app
    echo "PASS Homebrew install and app launch"
fi
