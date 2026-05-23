# Release

Use `scripts/release-notarized.sh` to create a Developer ID signed, notarized, stapled macOS release DMG.

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

## Build Release

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

Upload the final DMG from `build/release/` to the GitHub release. Do not upload `JustAboutTime-notary.zip`; it is only the temporary app notarization submission package.

## Optional Overrides

```sh
SCHEME="JustAboutTime" CONFIGURATION="Release" scripts/release-notarized.sh
```

Use `NOTARY_PROFILE="profile-name"` if you stored notarization credentials under a different keychain profile. Use `APPLE_TEAM_ID="team-id"` if signing with a different Apple Developer team.

Use `PROJECT_PATH=/path/to/JustAboutTime.xcodeproj` only if running the script from unusual tooling.
