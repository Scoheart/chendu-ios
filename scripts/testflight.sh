#!/usr/bin/env bash
# Archive 晨读 (Release, generic iOS device) and upload it to App Store Connect / TestFlight.
#
#   TEAM_ID=ABCDE12345 scripts/testflight.sh              # archive + upload
#   TEAM_ID=ABCDE12345 scripts/testflight.sh --archive-only
#
# Signing is automatic. Authentication, in order of preference:
#   1. App Store Connect API key, if all of ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8) are set;
#   2. otherwise the Apple account signed in to Xcode > Settings > Accounts.
# Either way -allowProvisioningUpdates lets Xcode create the distribution certificate/profile it needs.
#
# Build number: BUILD_NUMBER, else a UTC timestamp (yyyymmddHHMM), so every upload is higher than the last.
# Marketing version comes from MARKETING_VERSION in project.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --archive-only) ARCHIVE_ONLY=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

TEAM_ID="${TEAM_ID:-$(xcodebuild -project Chendu.xcodeproj -scheme Chendu -showBuildSettings 2>/dev/null | awk '/ DEVELOPMENT_TEAM = /{print $3; exit}')}"
if [[ -z "${TEAM_ID}" ]]; then
  echo "TEAM_ID is not set and the project has no DEVELOPMENT_TEAM." >&2
  echo "Find it at https://developer.apple.com/account (Membership details) and run: TEAM_ID=XXXXXXXXXX $0" >&2
  exit 1
fi

BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="build/testflight"
ARCHIVE="$OUT/Chendu-$BUILD_NUMBER.xcarchive"
mkdir -p "$OUT"

AUTH=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH not found: $ASC_KEY_PATH" >&2; exit 1; }
  AUTH+=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "auth: App Store Connect API key $ASC_KEY_ID"
else
  echo "auth: Apple account signed in to Xcode"
fi

echo "team: $TEAM_ID   build: $BUILD_NUMBER"

xcodebuild archive \
  -project Chendu.xcodeproj \
  -scheme Chendu \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}"

echo "archived: $ARCHIVE"
if [[ "$ARCHIVE_ONLY" == 1 ]]; then exit 0; fi

OPTIONS="$OUT/ExportOptions.plist"
cp scripts/ExportOptions.plist "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$OUT/export-$BUILD_NUMBER" \
  "${AUTH[@]}"

echo "uploaded build $BUILD_NUMBER. It shows up in App Store Connect > TestFlight after processing (usually 5–30 min)."
