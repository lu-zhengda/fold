# Release and CI lessons

Each entry: **date** — what happened — what changed (or what we learned).

---

## 2026-11-23

**Removed the weekly scheduled verify run.** `verify-release.yml` had a Monday `schedule:` cron that re-checked the latest release and Homebrew cask. GitHub Actions in this repo are CI/CD only; release verification belongs on `release: published` and optional `workflow_dispatch`, not on a calendar.

## 2026-11-23

**Added macOS CI and release verification workflows** (commit `61a082f`). The `test` job runs `./script/verify.sh --launch` (Swift tests, universal app packaging, DMG checks, launch smoke). `verify-release.sh` validates published GitHub assets and, with `--install-cask`, the live Homebrew cask against `lu-zhengda/tap/fold`.

## 2026-11-23

**Launch smoke uses the app executable on headless runners** (commit `d88c6dc`). Menu-bar apps do not always behave like a double-clicked `.app` in CI; `script/launch-smoke.swift` exercises the installed binary path used on unattended GitHub-hosted Mac runners.