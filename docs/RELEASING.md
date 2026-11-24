# Releasing Fold

## Current process (manual)

Today, cutting a release is done on a Mac with Xcode, a **Developer ID Application** identity, and App Store Connect API credentials for `notarytool`.

### 1. Set the version

Edit `Resources/Info.plist`: `CFBundleShortVersionString` and `CFBundleVersion`.

### 2. Build, sign, notarize, and staple

Run `script/release.sh` with:

| Variable | Purpose |
| --- | --- |
| `SIGNING_IDENTITY` | Developer ID Application identity (required) |
| `NOTARY_PROFILE` | Optional `notarytool` keychain profile name |
| `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | Alternative to `NOTARY_PROFILE` — passed to `xcrun notarytool` |

The script (sourcing `script/package.sh`):

1. Builds a universal `Fold.app` (arm64 + x86_64, macOS 14 minimum).
2. Signs the app with hardened runtime (`codesign --options runtime --timestamp`).
3. Zips the app, submits it to Apple notarization, staples the ticket, and checks with `spctl`.
4. Creates `Fold-<version>.dmg` (HFS+ UDZO with an Applications symlink), signs the image, notarizes and staples the DMG, and runs Gatekeeper checks.
5. Writes `dist/Fold-<version>.dmg` and `dist/checksums.txt` (SHA-256 of the DMG).

There is no release workflow in this repository yet; upload the assets to a GitHub Release and tag `v<version>` manually.

### 3. Homebrew cask

Update the `fold` cask in [lu-zhengda/homebrew-tap](https://github.com/lu-zhengda/homebrew-tap): `version`, download `url`, and `sha256` must match the published DMG and `checksums.txt`.

### 4. Automated verification

After a **stable** release is published on GitHub:

- **Verify published Fold** (`.github/workflows/verify-release.yml`) runs on `release: published`. Job `verify` calls `./script/verify-release.sh` with the tag (downloads the DMG and checksums, checks SHA-256, quarantine attributes, Developer ID + stapling via `script/verify-image.sh --distribution`). It does **not** install the cask unless triggered manually with the install option.

- **Manual re-check:** Actions → **Verify published Fold** → **Run workflow**. Optional inputs: version string, and whether to install the current cask (`--install-cask` path in `script/verify-release.sh`).

**CI** (`.github/workflows/ci.yml`, job `test`) exercises source builds on every push/PR to `main` via `./script/verify.sh --launch` (Swift tests, ad-hoc signed universal app, DMG checks, launch smoke).

---

## Planned: release on merge

Modeled on [lu-zhengda/updater `docs/RELEASING.md`](https://github.com/lu-zhengda/updater/blob/main/docs/RELEASING.md):

1. A pull request merged to `main` with **exactly one** of `semver:major`, `semver:minor`, or `semver:patch` triggers a release workflow (to be added).
2. CI imports the Developer ID certificate into a temporary keychain, runs the same signing/notarization steps as `script/release.sh`, and publishes a GitHub Release with `Fold-X.Y.Z.dmg` and `checksums.txt`.
3. A job using `HOMEBREW_TAP_TOKEN` bumps the `fold` cask in `lu-zhengda/homebrew-tap`.
4. **Verify published Fold** runs afterward (release event or an explicit follow-up job) to download the new assets and, when requested, install the cask on a clean runner.

Publishing will use GitHub-hosted `macos-latest` only (no self-hosted runners). Concurrent publishes will share a concurrency group so in-flight signing is not cancelled.

Manual `v*` tag pushes may remain as a fallback, similar to updater.

### Repository secrets (not yet configured)

| Secret | Role |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | Base64-encoded Developer ID `.p12` |
| `MACOS_CERT_PASSWORD` | Password for that `.p12` |
| `APPSTORE_API_KEY_ID` | App Store Connect API key ID |
| `APPSTORE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPSTORE_API_KEY_P8_BASE64` | Base64-encoded `.p8` API key |
| `HOMEBREW_TAP_TOKEN` | Token with push access to `lu-zhengda/homebrew-tap` |

Do not commit secret values. Configuration is pending before automated release-on-merge can run.