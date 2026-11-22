#!/bin/zsh
# Publishes a new version. Everyone running Grid Studio gets it the next time they open the app.
#
#   ./scripts/release.sh 1.1.0 "What changed, one line per item"
#
# What it does:
#   1. writes the version to VERSION and builds the signed app
#   2. notarizes it with Apple and staples the ticket (so it opens on any Mac)
#   3. zips it and signs the zip with the Sparkle key from your keychain
#   4. adds the version to appcast.xml, commits, tags and pushes
#   5. creates the GitHub release with the zip attached
#
# One time setup on the release Mac:
#   xcrun notarytool store-credentials GridStudio-notary --apple-id <you> --team-id <TEAM> --password <app specific password>
#   The Sparkle private key must be in the keychain (generate_keys --account GridStudio).
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: release.sh <version> \"notes\"}"
NOTES="${2:-Bug fixes and improvements.}"
REPO="adigold/GridStudio"
PROFILE="${NOTARY_PROFILE:-GridStudio-notary}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

[[ -z "$(git status --porcelain -- Sources Package.swift)" ]] || { echo "Commit your code changes first."; exit 1; }
grep -q "<sparkle:version>$NEW</sparkle:version>" appcast.xml && { echo "$NEW is already released."; exit 1; }

echo "$NEW" > VERSION
./scripts/build-app.sh

ZIP="build/Grid-Studio-$NEW.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Grid Studio.app" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "build/Grid Studio.app"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Grid Studio.app" "$ZIP"

SIG="$("$SPARKLE_BIN/sign_update" --account GridStudio "$ZIP")"   # sparkle:edSignature="..." length="..."
URL="https://github.com/$REPO/releases/download/v$NEW/Grid-Studio-$NEW.zip"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
HTML_NOTES="$(print -r -- "$NOTES" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | awk 'NF {print "<li>" $0 "</li>"}' | tr -d '\n')"

ITEM="    <item>
      <title>Version $NEW</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$NEW</sparkle:version>
      <sparkle:shortVersionString>$NEW</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$HTML_NOTES</ul>]]></description>
      <enclosure url=\"$URL\" type=\"application/octet-stream\" $SIG />
    </item>"
python3 - "$ITEM" <<'PY'
import sys
p = "appcast.xml"; s = open(p).read()
s = s.replace("<!-- RELEASES -->", "<!-- RELEASES -->\n" + sys.argv[1], 1)
open(p, "w").write(s)
PY

git add VERSION appcast.xml
git commit -m "Release $NEW"
git tag "v$NEW"
gh release create "v$NEW" "$ZIP" --repo "$REPO" --title "Grid Studio $NEW" --notes "$NOTES"
git push origin HEAD "v$NEW"   # appcast goes live last, after the zip is downloadable
echo "Released $NEW. Running copies will offer the update on their next launch."
