#!/usr/bin/env bash
# Builds a Release .app and packs it into build/TimesheetAssistant-<version>.dmg.
# Signs ad-hoc unless SIGN_IDENTITY is set (e.g. "Developer ID Application: ...").
# Model weights are never bundled; the build fails if any are found in the app.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="TimesheetAssistant"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
STAGE="$BUILD_DIR/dmg-stage"

xcodegen generate

xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

weights=$(find "$APP" \( -iname '*.safetensors' -o -iname '*.gguf' -o -iname '*.bin' -o -iname '*.npz' \) -print)
if [[ -n "$weights" ]]; then
  echo "error: model weights found inside the app bundle:" >&2
  echo "$weights" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
diskutil image create from --volumeName "Timesheet Assistant" --format UDZO "$STAGE" "$DMG"
rm -rf "$STAGE"

echo "Built $DMG"
