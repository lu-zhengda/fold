# Release and CI lessons

Each entry: **date** — what happened — what changed (or what we learned).

---

## 2026-11-24

**CI launch smoke now checks clipboard capture, not only that the process starts.** `ShelfStore` samples `NSPasteboard.general.changeCount` on a 0.45 second timer and stores one entry per payload digest, newest first; copying the same payload again moves that entry to the front. `./script/verify.sh --launch` writes three distinct strings (plain text, a URL, and a multi-line string) to the general pasteboard and reads `History.plist` from a temporary `--library-folder`. The folder override and `capture-status.txt` exist only when that argument is set. The check polls for up to 15 seconds per item and fails the `test` job with the expected and actual previews. `launch-smoke.swift --self-test` rejects a snapshot that is missing an item, so the failure path stays covered without leaving a broken expectation in the branch. UI scripting is not used; GitHub-hosted runners cannot grant Accessibility.

## 2026-11-24

**Release on merge replaces signing from a dev Mac.** `release-on-merge.yml` plans the tag from exactly one `semver:*` label (`script/plan-release.sh`, tested in CI by `script/test-plan-release.sh`), and `release-publish.yml` signs, notarizes, publishes, bumps `Casks/fold.rb`, and installs the cask on a clean runner. What we learned while wiring it:

- A release created with `GITHUB_TOKEN` does not fire `release: published`. Verification has to be a job in the release workflow; `verify-release.yml` is now manual only.
- `script/release.sh` signs the Sparkle `appcast.xml` with a key from the login keychain. CI needs that key as a secret (`SPARKLE_ED_PRIVATE_KEY`, passed with `generate_appcast --ed-key-file`), or the in-app update feed breaks.
- A manual release (v1.2.1) landed while the workflow was in review. The planner bumps from the latest stable git tag, never from `Info.plist`, so the first CI release is v1.2.2. Hand releases used small Sparkle build numbers (v1.2.1 is build 4); CI derives the build from the version (1.2.2 is 1002002), which stays higher, so installed copies still see CI releases as newer.
- Sparkle compares `CFBundleVersion`, which was hand-edited in `Info.plist`. The build number is now derived from the version (`bundle_build_number`) and stamped into the bundle, so a release can never ship a build number that is not newer.
- The tag is pushed only after the build job has signed, notarized, and verified the DMG. A failed build therefore leaves no tag without a release (updater's v0.24.1 lesson).
- `cancel-in-progress: false` still keeps only one pending run per group. Closed pull requests that cannot publish use their own group so they never replace a pending release.

## 2026-11-23

**Removed the weekly scheduled verify run.** `verify-release.yml` had a Monday `schedule:` cron that re-checked the latest release and Homebrew cask. GitHub Actions in this repo are CI/CD only; release verification belongs on `release: published` and optional `workflow_dispatch`, not on a calendar.

## 2026-11-23

**Added macOS CI and release verification workflows** (commit `61a082f`). The `test` job runs `./script/verify.sh --launch` (Swift tests, universal app packaging, DMG checks, launch smoke). `verify-release.sh` validates published GitHub assets and, with `--install-cask`, the live Homebrew cask against `lu-zhengda/tap/fold`.

## 2026-11-23

**Launch smoke uses the app executable on headless runners** (commit `d88c6dc`). Menu-bar apps do not always behave like a double-clicked `.app` in CI; `script/launch-smoke.swift` exercises the installed binary path used on unattended GitHub-hosted Mac runners.