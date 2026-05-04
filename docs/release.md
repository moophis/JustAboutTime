# Release

Use `scripts/release-notarized.sh` to create a Developer ID signed, notarized, stapled macOS release ZIP.

## Prerequisites

- Xcode command line tools installed.
- Apple Developer Program membership for the configured team.
- `Developer ID Application` certificate installed in the login keychain.
- Apple ID app-specific password for notarization.

## Credentials

Set credentials in the shell before running the release script:

```sh
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="53URGYWCC5"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Do not commit these values. `APPLE_APP_PASSWORD` is an app-specific password from appleid.apple.com, not the normal Apple ID password.

The script passes `APPLE_APP_PASSWORD` to `xcrun notarytool` as a command argument because this env-var-only flow intentionally avoids a stored keychain profile. Run it only on a trusted local machine; other local users or process monitors may be able to see command arguments while notarization is running.

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
6. Create `build/release/JustAboutTime-<version>.zip`.

Upload the final ZIP from `build/release/` to the GitHub release. Do not upload `JustAboutTime-notary.zip`; it is only the temporary notarization submission package.

## Optional Overrides

```sh
SCHEME="JustAboutTime" CONFIGURATION="Release" scripts/release-notarized.sh
```

Use `PROJECT_PATH=/path/to/JustAboutTime.xcodeproj` only if running the script from unusual tooling.
