#!/bin/zsh
# Builds "Grid Studio.app" into build/, as a universal binary (Apple silicon + Intel),
# with Sparkle embedded and everything signed with the Developer ID (hardened runtime).
#   SIGN_IDENTITY  the codesign identity (default: the Developer ID found in the keychain)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Grid Studio.app"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/adigold/GridStudio/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="+n791ZqQJ7jiFFaqbcorOqiSjMBDLPnYvxDgOjF42wc="
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then IDENTITY="-"; echo "No Developer ID found, signing ad hoc (runs on this Mac only)."; fi

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/GridStudio" "$APP/Contents/MacOS/Grid Studio"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Icon
TMP=$(mktemp -d)
swift scripts/make-icon.swift "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Grid Studio</string>
  <key>CFBundleDisplayName</key><string>Grid Studio</string>
  <key>CFBundleIdentifier</key><string>com.adigoldstein.gridstudio</string>
  <key>CFBundleExecutable</key><string>Grid Studio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Powered by AGsoundtrax LLC / Adi Goldstein. Copyright © 2026. monome grid is a product of monome.</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAllowsAutomaticUpdates</key><true/>
  <key>SUScheduledCheckInterval</key><integer>3600</integer>
</dict></plist>
PLIST

# Sign inside out: Sparkle's helpers, the framework, then the app.
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
[[ "$IDENTITY" == "-" ]] && SIGN=(codesign --force --sign -)
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $VERSION: $PWD/$APP"
