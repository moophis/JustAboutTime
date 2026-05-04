#!/usr/bin/env bash

set -euo pipefail

APP_NAME="JustAboutTime"
SCHEME="${SCHEME:-JustAboutTime}"
CONFIGURATION="${CONFIGURATION:-Release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/JustAboutTime.xcodeproj}"
EXPORT_OPTIONS_TEMPLATE="$ROOT_DIR/ExportOptions.plist"

BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.generated.plist"
NOTARY_ZIP="$BUILD_DIR/$APP_NAME-notary.zip"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "$name is required"
  fi
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "$name is required but was not found in PATH"
  fi
}

set_export_option() {
  local key="$1"
  local value="$2"

  if /usr/libexec/PlistBuddy -c "Set :$key $value" "$EXPORT_OPTIONS" >/dev/null 2>&1; then
    return
  fi

  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$EXPORT_OPTIONS"
}

require_env APPLE_ID
require_env APPLE_TEAM_ID
require_env APPLE_APP_PASSWORD

require_command ditto
require_command spctl
require_command xcodebuild
require_command xcrun

[[ -d "$PROJECT_PATH" ]] || fail "Xcode project not found: $PROJECT_PATH"
[[ -f "$EXPORT_OPTIONS_TEMPLATE" ]] || fail "Export options not found: $EXPORT_OPTIONS_TEMPLATE"

info "Preparing release directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

info "Archiving $APP_NAME"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_IDENTITY='Developer ID Application' \
  ENABLE_HARDENED_RUNTIME=YES

info "Generating Developer ID export options"
cp "$EXPORT_OPTIONS_TEMPLATE" "$EXPORT_OPTIONS"
set_export_option method developer-id
set_export_option signingStyle manual
set_export_option signingCertificate 'Developer ID Application'
set_export_option teamID "$APPLE_TEAM_ID"
set_export_option destination export

info "Exporting Developer ID signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || fail "exported app not found: $APP_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
FINAL_ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

info "Packaging app for notarization"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

info "Submitting notarization request"
xcrun notarytool submit "$NOTARY_ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

info "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

info "Assessing app with Gatekeeper"
spctl --assess --type execute --verbose=4 "$APP_PATH"

info "Creating final release ZIP"
rm -f "$FINAL_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

info "Release artifact ready: $FINAL_ZIP"
