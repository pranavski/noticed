#!/usr/bin/env bash
set -euo pipefail
UDID=6011A29C-EE1F-49AF-9C55-CB73A577AA20
BID=com.pranavsurampudi.noticed
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DD="${DERIVED_DATA:-$ROOT/DerivedData/screenshots}"
APP=$DD/Build/Products/Debug-iphonesimulator/Soma.app
OUT=$ROOT/DesignAssets/screenshots/iphone-6.9/raw
mkdir -p "$OUT"
xcodebuild -project "$ROOT/Soma.xcodeproj" -scheme Soma -configuration Debug -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" build -quiet
xcrun simctl boot $UDID 2>/dev/null || true
xcrun simctl bootstatus $UDID -b >/dev/null
xcrun simctl ui $UDID appearance light
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl uninstall $UDID $BID 2>/dev/null || true
xcrun simctl install $UDID "$APP"

shot() { # name consent envs...
  local name=$1 consent=$2; shift 2
  xcrun simctl terminate $UDID $BID 2>/dev/null || true
  if [ "$consent" = yes ]; then
    xcrun simctl spawn $UDID defaults write $BID soma.ai.parseConsent.v1 -bool YES
  else
    xcrun simctl spawn $UDID defaults delete $BID soma.ai.parseConsent.v1 2>/dev/null || true
  fi
  env SIMCTL_CHILD_SOMA_PREVIEW=1 "$@" xcrun simctl launch $UDID $BID >/dev/null
  sleep 5
  xcrun simctl io $UDID screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "$name"
}
shot 01-noticed yes SIMCTL_CHILD_SOMA_PREVIEW_TAB=insights
shot 02-today yes SIMCTL_CHILD_SOMA_PREVIEW_TAB=today
shot 03-capture yes SIMCTL_CHILD_SOMA_PREVIEW_TAB=today SIMCTL_CHILD_SOMA_PREVIEW_SHEET=capture
shot 04-compare-yesterday yes SIMCTL_CHILD_SOMA_PREVIEW_TAB=today SIMCTL_CHILD_SOMA_PREVIEW_COMPARE=1
shot 05-consent no SIMCTL_CHILD_SOMA_PREVIEW_TAB=insights
shot 06-kitchen yes SIMCTL_CHILD_SOMA_PREVIEW_TAB=settings
