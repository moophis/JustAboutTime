# Notarized Release Design

## Goal

Make downloadable macOS releases of JustAboutTime pass Gatekeeper without requiring users to bypass Apple malware verification.

## Current Problem

Version 1.0.1 is rejected by Gatekeeper with:

> Apple could not verify "JustAboutTime.app" is free of malware that may harm your Mac or compromise your privacy.

The repo currently has no notarization flow. `ExportOptions.plist` uses `codeSignIdentity` value `-`, which produces an ad-hoc signed export instead of a Developer ID signed app suitable for public distribution.

## Chosen Approach

Add local release automation that reads notarization credentials from environment variables. Do not commit secrets. Do not require a stored notarytool keychain profile.

The release flow will:

1. Archive the macOS app in Release configuration.
2. Export the app using Developer ID signing settings.
3. Package the exported app into a temporary ZIP for notarization.
4. Submit the package with `xcrun notarytool submit --wait`.
5. Staple the notarization ticket to `JustAboutTime.app`.
6. Verify the stapled app with Gatekeeper using `spctl`.
7. Create a DMG from the stapled app.
8. Sign the DMG with Developer ID.
9. Submit the signed DMG with `xcrun notarytool submit --wait`.
10. Staple the notarization ticket to the DMG.
11. Verify the DMG with Gatekeeper using `spctl --type open --context context:primary-signature`.

## Credentials

The script will require these environment variables:

- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_PASSWORD`: App-specific password for the Apple ID.

The Developer ID certificate must already be installed in the local login keychain. The script will fail early if credentials are missing or if codesigning/export fails.

## Files

- `scripts/release-notarized.sh`: Build, export, notarize, staple, and verify release artifact.
- `ExportOptions.plist`: Update for Developer ID export with manual signing and Developer ID Application certificate. The release script injects `teamID` from `APPLE_TEAM_ID` into a generated copy.
- `JustAboutTime.xcodeproj/project.pbxproj`: Enable hardened runtime for Release builds.
- `docs/release.md`: Document prerequisites, environment variables, and command usage.

## Artifact Layout

Use `build/release/` for generated output so release artifacts stay separate from Xcode DerivedData. The final artifact will be `JustAboutTime-<version>.dmg`, suitable for upload to a GitHub release.

## Error Handling

The script will use strict shell mode and explicit prerequisite checks. It will stop on the first failed command and print actionable messages for missing env vars, missing tools, signing failures, notarization failures, and Gatekeeper assessment failures.

## Verification

Successful release requires:

- `xcodebuild archive` succeeds.
- `xcodebuild -exportArchive` succeeds using Developer ID signing.
- `xcrun notarytool submit --wait` reports accepted status.
- `xcrun stapler staple` succeeds on `JustAboutTime.app`.
- `spctl --assess --type execute --verbose` accepts `JustAboutTime.app`.
- `hdiutil create` succeeds for the DMG built from the stapled app.
- `codesign --verify --strict --verbose` accepts the DMG.
- `xcrun notarytool submit --wait` accepts the DMG.
- `xcrun stapler staple` succeeds on the DMG.
- `spctl --assess --type open --context context:primary-signature --verbose` accepts the DMG.

## Out Of Scope

- GitHub Actions or other CI release automation.
- Storing notarization credentials in keychain profiles.
- Publishing the artifact to GitHub releases.
- Changing app behavior or UI.
