# Fold — agent guide

Fold is a local-only macOS clipboard-history app (Swift 5.10, SwiftPM). It lives in the menu bar and shows a horizontal shelf of recent clips. There is no network access, accounts, or telemetry.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/Fold/` | App entry, models, services, views |
| `Tests/FoldTests/` | Swift tests |
| `Resources/` | `Info.plist`, `Fold.icns` |
| `Package.swift` | SwiftPM package (executable `Fold`, macOS 14+) |
| `script/` | Build, verify, release, and packaging shell scripts |
| `.github/workflows/` | GitHub Actions (macOS CI) |

Packaging builds a universal `Fold.app` (arm64 + x86_64) via `script/package.sh`, used by verify and release scripts.

## Build and test

Requires a Mac with Xcode / Swift 5.10+ (macOS 14 SDK).

```sh
swift test
```

CI-equivalent local check (tests with coverage, ad-hoc signed universal app, DMG layout checks; optional GUI launch smoke):

```sh
./script/verify.sh          # same core steps as the `test` job (without coverage upload)
./script/verify.sh --launch # includes launch-smoke, like CI
```

`script/verify.sh` also syntax-checks `script/*.sh`, writes `.build/verification/coverage.json`, and runs `script/verify-image.sh` on a disposable DMG.

Quick dev loop:

```sh
./script/build_and_run.sh   # builds to `dist/Fold.app` and opens it
```

Release-quality signed/notarized builds use `script/release.sh` (see `docs/RELEASING.md`).

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
- **Release verify:** `.github/workflows/verify-release.yml` runs on `release: published` and `workflow_dispatch` (job `verify`).
- **Concurrency:** workflows use `concurrency` with `cancel-in-progress: true` on the same ref.

The `test` job runs `./script/verify.sh --launch` and uploads Swift coverage when present.

## Contributing

- Every change lands via pull request to `main` (squash merge).
- To **publish a new release**, add exactly one label on the PR: `semver:major`, `semver:minor`, or `semver:patch`. Automated release-on-merge is planned; see `docs/RELEASING.md`.
- Keep Fold **local-only:** no outbound network, sign-in, or analytics in app code or dependencies.
- **Public-repo hygiene:** never commit or paste machine hostnames, `/Users/...` paths, local temp directories, or raw local logs into PRs, issues, docs, or test fixtures. Use neutral placeholders in examples.

## Homebrew

The cask lives in [lu-zhengda/homebrew-tap](https://github.com/lu-zhengda/homebrew-tap) (`lu-zhengda/tap/fold`). Bumping the cask is part of the release process (manual today; planned automation).