# Release

## Prerequisites

- Xcode command line tools installed.
- Apple Developer Program membership for the configured team.
- `Developer ID Application` certificate installed in the login keychain.
- Apple ID app-specific password for notarization.

## Credentials

Store notarization credentials in Keychain once:

```sh
xcrun notarytool store-credentials "JustAboutTime-notary" \
  --apple-id "you@example.com" \
  --team-id "53URGYWCC5" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Do not commit these values. `APPLE_APP_PASSWORD` is an app-specific password from appleid.apple.com, not the normal Apple ID password. The release script uses the stored `JustAboutTime-notary` keychain profile, so the password is not passed as a command argument during release builds.

## Release Checklist

### 1. Pre-Release Checks

Check for uncommitted changes in all worktrees:

```sh
git worktree list
for wt in $(git worktree list --porcelain | grep "^worktree " | cut -d' ' -f2-); do
  echo "=== $wt ==="
  git -C "$wt" status --short
done
```

Check for unmerged worktree branches:

```sh
git branch --no-merged main
```

If anything is dirty or unmerged, resolve before proceeding.

### 2. Bump Version

Edit `JustAboutTime.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` → new semver (e.g. `1.0.7`)
- `CURRENT_PROJECT_VERSION` → increment build number (e.g. `7` → `8`)

Commit and tag:

```sh
git add JustAboutTime.xcodeproj/project.pbxproj
git commit -m "chore: bump version to <version> (build <n>)"
git tag -a v<version> -m "v<version>"
```

### 3. Build Notarized DMG

```sh
scripts/release-notarized.sh
```

The script will:

1. Archive `JustAboutTime` in Release configuration.
2. Export with Developer ID signing.
3. Submit a temporary ZIP to Apple notarization.
4. Staple the notarization ticket to `JustAboutTime.app`.
5. Verify the app with Gatekeeper.
6. Create `build/release/JustAboutTime-<version>.dmg` from the stapled app.
7. Sign the DMG with Developer ID.
8. Submit the signed DMG to Apple notarization.
9. Staple the notarization ticket to the DMG.
10. Verify the DMG with Gatekeeper.

### 4. Publish GitHub Release

Push the tag then create release with DMG asset:

```sh
git push origin v<version>
gh release create v<version> \
  --title "v<version>" \
  --notes "<release-notes>" \
  "build/release/JustAboutTime-<version>.dmg#JustAboutTime-<version>.dmg"
```

Do not upload `JustAboutTime-notary.zip`; it is only the temporary app notarization submission package.

### 5. Update Homebrew Cask

Clone the tap repo, update version + sha256, and push:

```sh
gh repo clone moophis/homebrew-tap /tmp/homebrew-tap
# Edit Casks/just-about-time.rb with new version and sha256
# Get sha256: shasum -a 256 build/release/JustAboutTime-<version>.dmg
git add Casks/just-about-time.rb
git commit -m "just-about-time <version>"
git push origin main
rm -rf /tmp/homebrew-tap
```

Wait a few seconds then verify:

```sh
brew update && brew info moophis/tap/just-about-time
```

## Optional Overrides

```sh
SCHEME="JustAboutTime" CONFIGURATION="Release" scripts/release-notarized.sh
```

Use `NOTARY_PROFILE="profile-name"` if you stored notarization credentials under a different keychain profile. Use `APPLE_TEAM_ID="team-id"` if signing with a different Apple Developer team.

Use `PROJECT_PATH=/path/to/JustAboutTime.xcodeproj` only if running the script from unusual tooling.
