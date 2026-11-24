# Fold — agent guide

Fold is a local-only macOS clipboard-history app (Swift 5.10, SwiftPM). It lives in the menu bar and shows recent clips in a split view. There is no network access, accounts, or telemetry.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/Fold/` | App entry, models, services, views |
| `Tests/FoldTests/` | Swift tests |
| `Resources/` | `Info.plist`, `Fold.icns` |
| `Package.swift` | SwiftPM package (executable `Fold`, macOS 26 minimum, macOS 26 and 27 supported) |
| `script/` | Build, verify, release, and packaging shell scripts |
| `.github/workflows/` | GitHub Actions (macOS CI) |

Packaging builds a universal `Fold.app` (arm64 + x86_64) via `script/package.sh`, used by verify and release scripts.

## Build and test

Use Xcode 26 or later. Fold supports the two most recent major versions of macOS.

```sh
swift test
```

CI-equivalent local check (tests with coverage, ad-hoc signed universal app, DMG layout checks; optional GUI launch smoke):

```sh
./script/verify.sh          # same core steps as the `test` job (without coverage upload)
./script/verify.sh --launch # includes launch-smoke, like CI
```

`script/verify.sh` also syntax-checks `script/*.sh`, runs `script/test-plan-release.sh` (release tag planning against a throwaway git repo), stamps the bundle version with `stamp_version`, writes `.build/verification/coverage.json`, and runs `script/verify-image.sh` on a disposable DMG.

## Clipboard history behavior check

`./script/verify.sh --launch` is the local command, and it is what the CI `test` job runs. After the app is up, the launch smoke copies three strings onto the system pasteboard: plain text, one `https` URL, and one multi-line string. It polls up to 15 seconds per copy and expects them in clipboard history newest-first. Copying the first string again must move that entry to the front and must not add a fourth row. `ShelfStore` polls `NSPasteboard.general.changeCount` every 0.45 seconds, and `Library.record` deduplicates by payload digest.

The smoke launch passes `--library-folder` with a directory created under the `mktemp` workspace (`$TMPDIR`). When that argument is present, Fold writes `History.plist` and a one-line `capture-status.txt` there. A normal launch keeps using Application Support. The script terminates the app on the way out, and `verify.sh` traps exit and signals so a failed run still kills the process id it recorded and deletes the temporary workspace. Checker-only (no app launch):

```sh
swift script/launch-smoke.swift --self-test
```

That command feeds the order checker a snapshot that is missing an item and exits successfully only if the checker rejects it.

Quick dev loop:

```sh
./script/build_and_run.sh   # builds to `dist/Fold.app` and opens it
```

Releases are cut by merging a labeled pull request; the release workflow runs `script/release.sh` on a GitHub-hosted runner (see `docs/RELEASING.md`). `script/release.sh` can still run on a Mac with a Developer ID identity for local testing, but do not publish from a dev Mac.

Published-release verification (download, checksum, Gatekeeper, optional Homebrew cask install):

```sh
./script/verify-release.sh [vX.Y.Z]
./script/verify-release.sh --install-cask
```

## Continuous integration

- **Runner:** `macos-latest` only (GitHub-hosted). This is a public repo — do not add self-hosted runners.
- **Required status check:** the `test` job in `.github/workflows/ci.yml` (workflow name **CI**).
- **Triggers:** `push` / `pull_request` to `main`, `workflow_dispatch`.
- **Actions:** every `uses:` must stay pinned to a full commit SHA (repository policy). Do not add unpinned or floating action refs.
- **Schedules:** no `schedule:` triggers — workflows are CI/CD only, not cron jobs.
- **Release:** `.github/workflows/release-on-merge.yml` runs on `pull_request: closed` (merged only) and `workflow_dispatch` (bump input), plans the tag with `script/plan-release.sh`, and calls `.github/workflows/release-publish.yml` (jobs `build`, `publish`, `homebrew-cask`, `verify-published-release`). It never runs on pull request opened/synchronize.
- **Release verify:** `.github/workflows/verify-release.yml` is `workflow_dispatch` only (job `verify`) for re-checking a published release. Releases made with `GITHUB_TOKEN` do not fire `release: published`, so the release workflow verifies inline.
- **Concurrency:** CI and verify workflows use `cancel-in-progress: true` on the same ref. The release workflow is the exception: one `fold-release` group with `cancel-in-progress: false`, so a signing run is never cancelled.

The `test` job runs `./script/verify.sh --launch` and uploads Swift coverage when present.

## Contributing

- Every change lands via pull request to `main` (squash merge).
- For PRs that ship user-facing changes, apply exactly one release label. Use `semver:minor` for backward-compatible features, `semver:patch` for bug fixes, and `semver:major` for breaking changes. Leave docs-only and CI-only PRs unlabeled.
- **Before enabling auto-merge or merging manually**, verify the labels on the GitHub PR. The release workflow reads them at merge time and publishes only when exactly one semver label is present.
- If a release label was missed, check published releases and active release runs first. If the change still needs a release, dispatch `release-on-merge.yml` on `main` with the intended `bump`. This publishes the current head of `main`. See [release recovery](docs/RELEASING.md#recovery).
- Keep Fold **local-only:** no outbound network, sign-in, or analytics in app code or dependencies.
- **Public-repo hygiene:** never commit or paste machine hostnames, `/Users/...` paths, local temp directories, or raw local logs into PRs, issues, docs, or test fixtures. Use neutral placeholders in examples.

## Homebrew

The cask lives in [lu-zhengda/homebrew-tap](https://github.com/lu-zhengda/homebrew-tap) (`lu-zhengda/tap/fold`). The `homebrew-cask` release job updates `version` and `sha256` in `Casks/fold.rb` and commits `fold X.Y.Z` to the tap's default branch with `HOMEBREW_TAP_TOKEN`. Do not edit the cask by hand for a release.
