# Releasing Fold

Releases are published by GitHub Actions on GitHub-hosted `macos-latest` runners. Nothing is signed or uploaded from a personal Mac. The workflows are modeled on [lu-zhengda/updater](https://github.com/lu-zhengda/updater/blob/main/docs/RELEASING.md).

## Cut a release

Add exactly one of these labels to the pull request before you merge it into `main`. The bump applies to the latest stable `vX.Y.Z` tag at merge time; pre-release tags are ignored.

| Label | Bump | From `v1.1.0` |
| --- | --- | --- |
| `semver:patch` | patch | `v1.1.1` |
| `semver:minor` | minor | `v1.2.0` |
| `semver:major` | major | `v2.0.0` |

- **No semver label:** the workflow succeeds without publishing. Leave docs-only and CI-only pull requests unlabeled.
- **More than one semver label:** the workflow logs a warning and publishes nothing. To publish, run the workflow manually (see [Recovery](#recovery)).
- Other labels can sit next to the semver label and do not affect the bump.
- The version comes from the tag. `Resources/Info.plist` in the source tree is not edited or committed back; the version is stamped into the built bundle.

Pull requests from forks get no secrets on `pull_request` events, so they cannot publish when merged. Merge them, then run the workflow manually.

## What runs

[`.github/workflows/release-on-merge.yml`](../.github/workflows/release-on-merge.yml) runs when a pull request into `main` is closed, and on `workflow_dispatch`. It never runs when a pull request is opened or updated. CI's `test` job runs `script/test-plan-release.sh`, which exercises the planner against a throwaway repository without any secrets.

1. **`plan`** (`contents: read`). Skips closed pull requests that were not merged. Checks out the merge commit (or, for a manual run, `main`) and runs [`script/plan-release.sh`](../script/plan-release.sh), which:
   - counts the semver labels;
   - requires the target commit to be on `main`;
   - computes the next tag, its version, and the build number.

   If the commit already has a stable tag but no GitHub Release, the planner resumes that tag. If the tag already has a release, nothing is published.
2. **`release`** calls [`.github/workflows/release-publish.yml`](../.github/workflows/release-publish.yml), which has four jobs:
   - **`build`** (`contents: read`, signing secrets):
     - Runs `swift test`.
     - Imports the Developer ID certificate into a temporary keychain and runs [`script/release.sh`](../script/release.sh) with `RELEASE_VERSION`. That script builds the universal app (`script/package.sh`), stamps `CFBundleShortVersionString` and `CFBundleVersion`, and signs with hardened runtime and a secure timestamp.
     - Notarizes and staples `Fold.app`, then builds `Fold-X.Y.Z.dmg`, signs it, and notarizes and staples it.
     - Writes `checksums.txt` and the Sparkle `appcast.xml`.
     - Before anything is published, runs `script/verify-image.sh --distribution` on the DMG. This checks Gatekeeper, stapling, the Developer ID requirement, the version and build, and the appcast signature.
     - Uploads the three files as a workflow artifact. Deletes the keychain and key files in an `always()` step.
   - **`publish`** (`contents: write`, no signing secrets):
     - Downloads the artifact and re-checks the SHA-256.
     - Creates the annotated tag `vX.Y.Z` on the release commit, or accepts an existing tag only if it points at that commit.
     - Creates the GitHub Release `Fold X.Y.Z` with `Fold-X.Y.Z.dmg`, `checksums.txt`, and `appcast.xml`. The release notes start with the merged pull request's title and link, followed by GitHub's generated notes.
   - **`homebrew-cask`** (no `GITHUB_TOKEN` permissions; uses `HOMEBREW_TAP_TOKEN`):
     - Clones [lu-zhengda/homebrew-tap](https://github.com/lu-zhengda/homebrew-tap) and sets `version` and `sha256` in `Casks/fold.rb`. The cask `url` interpolates the version, so it is left alone; the job fails if the url no longer points at `Fold-#{version}.dmg`.
     - Commits `fold X.Y.Z` directly to the tap's default branch. The token goes in an HTTP header that is masked and never printed.
   - **`verify-published-release`** (`contents: read`): runs `script/verify-release.sh --install-cask vX.Y.Z` on a clean runner.
     - Downloads the release assets and checks `checksums.txt`, then checks the DMG and the app inside it (Developer ID requirement, `xcrun stapler validate`, Gatekeeper).
     - Taps `lu-zhengda/tap` fresh, checks the cask's version, sha256, and url, and runs `brew install --cask lu-zhengda/tap/fold`.
     - On `/Applications/Fold.app`, runs `codesign --verify --deep --strict` and `xcrun stapler validate`, requires `spctl --assess --type execute -vv` to report `accepted` with `source=Notarized Developer ID`, checks both bundle versions, and launches the app.

A release created with `GITHUB_TOKEN` does not trigger `release: published`, so this verification runs inside the release workflow rather than in `verify-release.yml`.

### Concurrency

Runs that can publish (merged pull requests with a semver label, and manual runs) share one concurrency group, `fold-release`, with `cancel-in-progress: false`. A second merge waits for the first; it never cancels a run that is signing or tagging. GitHub keeps only one *pending* run per group, so if three labeled pull requests merge while a release is running, the middle one is cancelled before it starts. It then shows as cancelled; publish it with a manual run. Closed pull requests that cannot publish use a per-run group so they never displace a pending release.

### Version and build number

Sparkle offers an update when the feed's `CFBundleVersion` is greater than the installed one. `bundle_build_number` in `script/package.sh` derives it from the version as `major * 1000000 + minor * 1000 + patch` (for example `1.2.0` → `1002000`), so it always increases with the tag. Each component must be 0–999. `stamp_version` writes both keys into the built bundle; `script/verify.sh` does the same in CI.

### Signing

- The `.p12` must contain exactly one code-signing identity: **Developer ID Application** for team `XY7H3QGJ2T`. The job stops if it finds anything else and signs with that identity's SHA-1 hash.
- The keychain is created in `$RUNNER_TEMP` with a random password, which is masked. The job sets it as the default keychain and the only one in the user search list, and runs `security set-key-partition-list` so `codesign` never prompts. The `always()` cleanup step deletes it.
- Fold has no entitlements file. The app is signed with hardened runtime and no entitlements. `embed_sparkle` signs Sparkle's `Autoupdate` and `Updater.app` the same way before the app bundle is signed.
- The App Store Connect key is decoded to a file in `$RUNNER_TEMP` and passed to `notarytool --key/--key-id/--issuer`. If a submission is not `Accepted`, the job prints `xcrun notarytool log` for it and fails.

## Secrets

Set these under **Settings → Secrets and variables → Actions** in `lu-zhengda/fold`. Secret values are never printed; values the workflow derives from them are masked.

| Secret | Format |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Base64 of the password-protected `.p12` holding only the Developer ID Application certificate and its private key, on one line |
| `MACOS_CERT_PASSWORD` | Export password of that `.p12` |
| `APPSTORE_API_KEY_P8_BASE64` | Base64 of `AuthKey_<KeyID>.p8` (PKCS#8 PEM), on one line |
| `APPSTORE_API_KEY_ID` | App Store Connect API key ID |
| `APPSTORE_API_ISSUER_ID` | App Store Connect issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key matching `SUPublicEDKey` in `Resources/Info.plist` |
| `HOMEBREW_TAP_TOKEN` | Token that can push to `lu-zhengda/homebrew-tap` |

Read each value from a file or stdin so it never appears in shell history or the process list:

```sh
REPO=lu-zhengda/fold
base64 < developer-id.p12 | tr -d '\n' | gh secret set MACOS_CERT_P12_BASE64 --repo "$REPO"
gh secret set MACOS_CERT_PASSWORD --repo "$REPO" < p12-password.txt
base64 < AuthKey_KEYID.p8 | tr -d '\n' | gh secret set APPSTORE_API_KEY_P8_BASE64 --repo "$REPO"
gh secret set APPSTORE_API_KEY_ID --repo "$REPO" < key-id.txt
gh secret set APPSTORE_API_ISSUER_ID --repo "$REPO" < issuer-id.txt
gh secret set HOMEBREW_TAP_TOKEN --repo "$REPO" < tap-token.txt
```

To export the Sparkle key from the login keychain that `script/release.sh` used before, use Sparkle's `generate_keys` (built by SwiftPM under `.build/artifacts/sparkle/Sparkle/bin/`):

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account local.fold.clipboard -x sparkle-private-key.txt
gh secret set SPARKLE_ED_PRIVATE_KEY --repo lu-zhengda/fold < sparkle-private-key.txt
```

Delete the exported files afterwards. The build job checks `appcast.xml` against `SUPublicEDKey` in the signed app, so a wrong key fails before anything is published.

## Recovery

| Situation | What to do |
| --- | --- |
| `build` failed (tests, signing, notarization, verification) | Nothing was tagged or published. Fix the cause and **Re-run failed jobs**, or merge the fix with the semver label. |
| `publish` failed after pushing the tag | **Re-run failed jobs**. The job accepts the tag because it points at the same commit, and deletes a draft release left by an interrupted upload. Re-running the whole workflow also works: the planner resumes the tag because it has no release yet. |
| `homebrew-cask` failed | **Re-run failed jobs**. The edit is idempotent, and the push is tried up to three times, rebasing after each rejection. |
| `verify-published-release` failed | The release and cask are already public. Read the failing check, fix forward with a new patch release if needed, then re-run the job or use **Verify published Fold**. |
| Label forgotten, two semver labels, a pending run cancelled, or a fork pull request | **Actions → Release on merge → Run workflow** on `main`, and choose `patch`, `minor`, or `major`. This releases the current `main` head. |

Do not create tags, GitHub Releases, or tap commits by hand. A commit that already has a published release is never released again, and a tag on another commit is never moved.

## Re-verify a published release

**Actions → Verify published Fold → Run workflow**. Leave the version blank for the latest release, or enter `X.Y.Z`. The optional cask install runs the same `script/verify-release.sh --install-cask` path as `verify-published-release`. Locally:

```sh
./script/verify-release.sh [vX.Y.Z]
./script/verify-release.sh --install-cask   # disposable machines only
```

## Local signed builds

`script/release.sh` still works on a Mac for testing signing changes. It reads the version from `RELEASE_VERSION` or `Resources/Info.plist`. Set `SIGNING_IDENTITY`, plus either `NOTARY_PROFILE` or `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`. It reads the Sparkle key from the login keychain unless `SPARKLE_ED_KEY_FILE` is set. It writes `dist/Fold-<version>.dmg`, `dist/checksums.txt`, and `dist/appcast.xml`. Do not upload these files; publishing goes through the workflow.
