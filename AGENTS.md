# Release process

When user says "prepare release", "cut release", "bump version", or "make and publish new release":

### 0. Prerequisites (one-time setup)
- `xcrun notarytool store-credentials "JustAboutTime-notary" --apple-id "you@example.com" --team-id "53URGYWCC5" --password "xxxx-xxxx-xxxx-xxxx"` — app-specific password from appleid.apple.com
- Sparkle private Ed25519 key must be in login keychain under account `JustAboutTime` (service `Sparkle`):
  - If key file exists: `security import <key-file>.pem -k ~/Library/Keychains/login.keychain-db` (then rename service to `Sparkle`)
  - Check: `security find-generic-password -a "JustAboutTime" -w`

### 1. Pre-release checks
- `git worktree list` + check each worktree is clean
- `git branch --no-merged main` — nothing should appear
- If dirty/unmerged, resolve before proceeding

### 2. Ask user for version + notes
- "What version + release notes?"
- Derive build number: grep CURRENT_PROJECT_VERSION, current is `N`, new is `N+1`

### 3. Bump version
- `grep MARKETING_VERSION|CURRENT_PROJECT_VERSION in project.pbxproj` to find current values
- Edit `JustAboutTime.xcodeproj/project.pbxproj`:
  - `MARKETING_VERSION = X.Y.Z` → new semver (use `replaceAll: true` — appears in 2 configs)
  - `CURRENT_PROJECT_VERSION = N` → N+1 (use `replaceAll: true` — appears in 4 configs)
- `git add JustAboutTime.xcodeproj/project.pbxproj`
- `git commit -m "chore: bump version to <version> (build <N+1>)"`
- `git tag -a v<version> -m "v<version>"`

### 4. Build notarized DMG + Sparkle artifacts
- Run `scripts/release-notarized.sh` directly (not via subagent — needs Xcode + notary credentials)
- Takes ~5 min
- Outputs:
  - `build/release/JustAboutTime-<version>.dmg` — for Homebrew / direct download
  - `build/release/JustAboutTime-<version>.zip` — for Sparkle update download
  - `build/release/appcast.xml` — Sparkle appcast feed (auto-generated if key + tool available)
- If `appcast.xml` was NOT auto-generated (missing key/tool), generate manually:
  - `generate_appcast --account JustAboutTime build/release/`
  - (Tool location: Sparkle SPM artifact in DerivedData)

### 5. Publish GitHub release
- `git push origin v<version>`
- `gh release create v<version> --title "v<version>" --notes "<release-notes>" "build/release/JustAboutTime-<version>.dmg#JustAboutTime-<version>.dmg" "build/release/JustAboutTime-<version>.zip#JustAboutTime-<version>.zip" "build/release/appcast.xml#appcast.xml"`
- Do NOT upload `JustAboutTime-notary.zip`

### 6. Update Homebrew cask
- `git clone https://github.com/moophis/homebrew-tap.git /tmp/homebrew-tap-<version>`
- Edit `/tmp/homebrew-tap-<version>/Casks/just-about-time.rb`:
  - Update `version` string
  - Update `sha256` from `shasum -a 256 build/release/JustAboutTime-<version>.dmg`
- `git add Casks/just-about-time.rb && git commit -m "just-about-time <version>" && git push origin main`
- Clean up: release agent cleans `/tmp/homebrew-tap-<version>` at end

### 7. Verify
- `brew update && brew info moophis/tap/just-about-time` — should show new version
