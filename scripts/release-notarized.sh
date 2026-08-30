#!/usr/bin/env bash

set -euo pipefail

APP_NAME="JustAboutTime"
SCHEME="${SCHEME:-JustAboutTime}"
CONFIGURATION="${CONFIGURATION:-Release}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-53URGYWCC5}"
NOTARY_PROFILE="${NOTARY_PROFILE:-JustAboutTime-notary}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/JustAboutTime.xcodeproj}"
EXPORT_OPTIONS_TEMPLATE="$ROOT_DIR/ExportOptions.plist"

BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.generated.plist"
DMG_ROOT="$BUILD_DIR/dmg-root"
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

require_command ditto
require_command hdiutil
require_command spctl
require_command codesign
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
FINAL_DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

info "Packaging app for notarization"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

info "Submitting notarization request"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

info "Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

info "Assessing app with Gatekeeper"
spctl --assess --type execute --verbose=4 "$APP_PATH"

info "Creating DMG"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$FINAL_DMG"

info "Signing DMG"
codesign --sign 'Developer ID Application' \
  --timestamp \
  --options runtime \
  "$FINAL_DMG"
codesign --verify --strict --verbose=4 "$FINAL_DMG"

info "Submitting DMG notarization request"
xcrun notarytool submit "$FINAL_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

info "Stapling DMG notarization ticket"
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"

info "Assessing DMG with Gatekeeper"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"

info "Creating Sparkle-compatible zip"
SPARKLE_ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$SPARKLE_ZIP"

info "Generating appcast.xml"
rm -f "$NOTARY_ZIP"

GENERATE_APPCAST=$(find "$ROOT_DIR" ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle/bin/generate_appcast" -type f 2>/dev/null | head -1)
APPCAST="$BUILD_DIR/appcast.xml"
if [[ -n "$GENERATE_APPCAST" ]]; then
  if security find-generic-password -a "JustAboutTime" -w &>/dev/null; then
    APPCAST_INPUT_DIR="$BUILD_DIR/appcast-input"
    rm -rf "$APPCAST_INPUT_DIR"
    mkdir -p "$APPCAST_INPUT_DIR"
    cp "$SPARKLE_ZIP" "$APPCAST_INPUT_DIR/"
    "$GENERATE_APPCAST" --account "JustAboutTime" "$APPCAST_INPUT_DIR"
    mv "$APPCAST_INPUT_DIR/appcast.xml" "$APPCAST"
    rm -rf "$APPCAST_INPUT_DIR"
    if [[ -f "$APPCAST" ]]; then
      info "Appcast generated: $APPCAST"
    else
      info "Warning: generate_appcast ran but appcast.xml not found"
    fi
  else
    info "Warning: Sparkle private key not found in keychain (account: JustAboutTime). Skipping generate_appcast."
    info "  Install key first, then run: $GENERATE_APPCAST --account JustAboutTime $BUILD_DIR"
  fi
else
  info "Warning: generate_appcast binary not found. Install Sparkle CLI tools."
fi

info "Release artifacts ready:"
info "  DMG:   $FINAL_DMG"
info "  ZIP:   $SPARKLE_ZIP"
if [[ -f "$APPCAST" ]]; then
  info "  Appcast: $APPCAST"
fi
