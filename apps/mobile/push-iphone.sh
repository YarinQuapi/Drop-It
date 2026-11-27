#!/usr/bin/env bash
# Build the latest release and update it on a paired iPhone.
# The app is upgraded in place (no uninstall), so its data and the "trust this
# developer" approval on the phone are kept. It does not open the app.
# Every run re-signs the app and its widget together. Free Apple profiles last
# 7 days, so run it at least weekly.
# Usage: ./push-iphone.sh [device-id]

set -euo pipefail

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH." >&2
  exit 1
fi

device_id="${1:-${DROPIT_DEVICE:-}}"
device_name=""

if [[ -z "$device_id" ]]; then
  set +e
  selection="$(flutter devices --machine | python3 -c '
import json, sys
devices = json.load(sys.stdin)
phones = [d for d in devices if d.get("targetPlatform") == "ios" and not d.get("emulator")]
if not phones:
    sys.exit(2)
if len(phones) > 1:
    for d in phones:
        print(d["id"] + "\t" + d["name"], file=sys.stderr)
    sys.exit(3)
print(phones[0]["id"] + "\t" + phones[0]["name"])
')"
  status=$?
  set -e
  if [[ "$status" -eq 2 ]]; then
    echo "No iPhone is connected. Unlock it, trust this Mac, and connect by cable or wirelessly." >&2
    exit 1
  fi
  if [[ "$status" -eq 3 ]]; then
    echo "More than one iPhone is connected. Run this again with the device id:" >&2
    exit 1
  fi
  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi
  device_id="${selection%%$'\t'*}"
  device_name="${selection#*$'\t'}"
fi

app="build/ios/iphoneos/Runner.app"
widget="$app/PlugIns/DropItWidget.appex"

# Xcode reuses a cached profile while it is still valid, so the widget can expire
# days before the app and silently stop updating. Set both profiles aside to get
# new ones; they are put back if the build fails.
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
backup="$(mktemp -d)"
built=0
cleanup() {
  if [[ "$built" -ne 1 ]]; then
    for file in "$backup"/*.mobileprovision; do
      if [[ -f "$file" ]]; then mv -n "$file" "$profiles/"; fi
    done
  fi
  rm -rf "$backup"
}
trap cleanup EXIT

for file in "$profiles"/*.mobileprovision; do
  [[ -f "$file" ]] || continue
  app_id="$(security cms -D -i "$file" 2>/dev/null |
    plutil -extract Entitlements.application-identifier raw - 2>/dev/null || true)"
  case "$app_id" in
    *.dev.yarinlevi.dropit | *.dev.yarinlevi.dropit.DropItWidget) mv "$file" "$backup/" ;;
  esac
done

echo "Building the release app..."
# Drop the previous bundles so no old profile stays embedded.
rm -rf "$app" build/ios/Release-iphoneos/Runner.app build/ios/Release-iphoneos/DropItWidget.appex
flutter build ios --release
built=1

expiry() {
  security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null |
    plutil -extract ExpirationDate raw -
}
app_expiry="$(expiry "$app")"
widget_expiry="$(expiry "$widget")"
echo "Signed until: app ${app_expiry}, widget ${widget_expiry} (UTC)."
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"

if [[ -n "$device_name" ]]; then
  echo "Installing ${bundle} on ${device_name}..."
else
  echo "Installing ${bundle} on ${device_id}..."
fi
# The first attempt can hit a sleeping or locked phone ("Connection reset by
# peer"); it wakes the connection, so retry a few times.
installed=0
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$device_id" "$app"; then
    installed=1
    break
  fi
  echo "Install attempt ${attempt} failed. Keep the iPhone unlocked; retrying..." >&2
  sleep 3
done
if [[ "$installed" -ne 1 ]]; then
  echo "Could not reach the iPhone. Unlock it and connect by cable (or make sure it is on the same Wi-Fi), then run this again." >&2
  exit 1
fi
echo "Updated. Open Drop It on the iPhone to refresh the widget."
