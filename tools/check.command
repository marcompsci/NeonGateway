#!/bin/bash
# Neon Getaway check: GameCore unit tests, then an iPhone Simulator build, install, launch and
# screenshot. Double-click in Finder, or run from Terminal. Summary: Logs/check.txt
cd "$(dirname "$0")/.." || exit 1
mkdir -p Logs
rm -f Logs/check_finished Logs/sim_launch.png
SUMMARY=Logs/check.txt
SIM_NAME="${NG_SIM:-iPhone 17 Pro}"
BUNDLE=com.phoronomicstudios.neongetaway
# Optional: Logs/check_args holds launch arguments for this one run (e.g. -NGAutoJob coldCrate
# -NGAutopilot YES); a second screenshot is then taken AFTER_DELAY seconds later.
LAUNCH_ARGS=$(cat Logs/check_args 2>/dev/null)
rm -f Logs/check_args Logs/sim_after.png
# Optional: Logs/check_mode = "uitest" (also run the UI smoke tests), "testflight" (archive + upload
# to App Store Connect, only if tests and the build pass) or "device" (also build
# Release, install and launch on a connected iPhone). Used once, then removed.
MODE=$(cat Logs/check_mode 2>/dev/null)
rm -f Logs/check_mode
AFTER_DELAY="${NG_AFTER_DELAY:-28}"
# Optional: Logs/check_delay overrides that wait for one run (seconds).
if [ -f Logs/check_delay ]; then AFTER_DELAY=$(cat Logs/check_delay); rm -f Logs/check_delay; fi

echo "Neon Getaway check — $(date)" > "$SUMMARY"
xcodebuild -version >> "$SUMMARY" 2>&1

echo "== GameCore: swift test ==" | tee -a "$SUMMARY"
swift test --package-path Packages/GameCore > Logs/swift_test.log 2>&1
ST=$?
grep -E "Executed [0-9]+ test|error:|failed \(" Logs/swift_test.log | sort -u | tail -n 40 >> "$SUMMARY"
echo "swift test exit code: $ST" | tee -a "$SUMMARY"

# Pick the simulator by name; fall back to the first available iPhone.
SIM_ID=$(xcrun simctl list devices available | grep -m1 "    $SIM_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -z "$SIM_ID" ]; then
  SIM_ID=$(xcrun simctl list devices available | grep -m1 "    iPhone" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
fi
echo "Simulator: $SIM_ID" | tee -a "$SUMMARY"

echo "== App: xcodebuild (Simulator, Debug) ==" | tee -a "$SUMMARY"
xcodebuild -project NeonGetaway.xcodeproj -scheme NeonGetaway -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath Build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build > Logs/xcodebuild.log 2>&1
XB=$?
grep -E "(error|warning): " Logs/xcodebuild.log | grep -v "^ld: warning" | sort -u | head -n 80 >> "$SUMMARY"
tail -n 3 Logs/xcodebuild.log >> "$SUMMARY"
echo "xcodebuild exit code: $XB" | tee -a "$SUMMARY"

if [ $XB -eq 0 ] && [ -n "$SIM_ID" ]; then
  echo "== Simulator: install + launch ==" | tee -a "$SUMMARY"
  xcrun simctl boot "$SIM_ID" 2>/dev/null
  open -a Simulator --args -CurrentDeviceUDID "$SIM_ID"
  xcrun simctl bootstatus "$SIM_ID" -b > /dev/null 2>&1
  APP=Build/DerivedData/Build/Products/Debug-iphonesimulator/NeonGetaway.app
  xcrun simctl terminate "$SIM_ID" "$BUNDLE" 2>/dev/null
  xcrun simctl install "$SIM_ID" "$APP" >> "$SUMMARY" 2>&1
  echo "launch args: ${LAUNCH_ARGS:-none}" | tee -a "$SUMMARY"
  # shellcheck disable=SC2086
  xcrun simctl launch "$SIM_ID" "$BUNDLE" $LAUNCH_ARGS >> "$SUMMARY" 2>&1
  LAUNCH=$?
  sleep 6
  xcrun simctl io "$SIM_ID" screenshot Logs/sim_launch.png > /dev/null 2>&1
  echo "launch exit code: $LAUNCH" | tee -a "$SUMMARY"
  if xcrun simctl spawn "$SIM_ID" launchctl list 2>/dev/null | grep -q "$BUNDLE"; then
    echo "app running after 6 s: yes" | tee -a "$SUMMARY"
  else
    echo "app running after 6 s: NO" | tee -a "$SUMMARY"
  fi
  if [ -n "$LAUNCH_ARGS" ]; then
    sleep "$AFTER_DELAY"
    xcrun simctl io "$SIM_ID" screenshot Logs/sim_after.png > /dev/null 2>&1
    echo "second screenshot after $((AFTER_DELAY + 6)) s: Logs/sim_after.png" | tee -a "$SUMMARY"
  fi
fi

if [ "$MODE" = "uitest" ] && [ $XB -eq 0 ]; then
  echo "== UI smoke tests (Simulator) ==" | tee -a "$SUMMARY"
  xcodebuild -project NeonGetaway.xcodeproj -scheme NeonGetaway -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath Build/DerivedData \
    CODE_SIGNING_ALLOWED=NO test > Logs/uitest.log 2>&1
  UT=$?
  grep -E "Test Case .* (passed|failed)|error:|Executed [0-9]+ test" Logs/uitest.log | sort -u | tail -n 30 >> "$SUMMARY"
  echo "UI test exit code: $UT" | tee -a "$SUMMARY"
fi

# Signing profiles downloaded from the developer portal (Logs/*.mobileprovision) are installed
# where Xcode looks for them. Xcode has no account signed in on this Mac, so device builds sign
# manually with the "Neon Getaway Dev" profile (Game Center + iCloud).
install_profiles() {
  for f in Logs/*.mobileprovision; do
    [ -e "$f" ] || continue
    uuid=$(security cms -D -i "$f" 2>/dev/null | plutil -extract UUID raw - 2>/dev/null)
    [ -n "$uuid" ] || continue
    for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
               "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
      mkdir -p "$dir" && cp "$f" "$dir/$uuid.mobileprovision"
    done
    echo "installed profile $(basename "$f") ($uuid)" | tee -a "$SUMMARY"
  done
}

if [ "$MODE" = "device" ]; then
  echo "== Device: Release build, install, launch ==" | tee -a "$SUMMARY"
  install_profiles
  xcodebuild -project NeonGetaway.xcodeproj -scheme NeonGetaway -configuration Release \
    -destination "generic/platform=iOS" -derivedDataPath Build/DeviceData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=X6LZQ3FS36 \
    PROVISIONING_PROFILE_SPECIFIER="Neon Getaway Dev" build > Logs/device_build.log 2>&1
  DB=$?
  grep -E "(error|warning): " Logs/device_build.log | grep -v "^ld: warning" | sort -u | head -n 30 >> "$SUMMARY"
  tail -n 2 Logs/device_build.log >> "$SUMMARY"
  echo "device build exit code: $DB" | tee -a "$SUMMARY"
  xcrun devicectl list devices --json-output Logs/devices.json > Logs/devices.txt 2>&1
  # Every paired iPhone that isn't marked unavailable gets the build: connected ones first,
  # then ones on the same Wi-Fi (devicectl wakes the connection on demand).
  DEV_IDS=$(/usr/bin/python3 - <<'PY'
import json
try:
    devices = json.load(open("Logs/devices.json"))["result"]["devices"]
except Exception:
    devices = []
rank = {"connected": 0, "disconnected": 1}
phones = [d for d in devices if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("connectionProperties", {}).get("tunnelState") in rank]
phones.sort(key=lambda d: rank[d["connectionProperties"]["tunnelState"]])
print(" ".join(d["identifier"] for d in phones))
PY
)
  cat Logs/devices.txt >> "$SUMMARY"
  echo "devices: ${DEV_IDS:-none reachable}" | tee -a "$SUMMARY"
  if [ $DB -eq 0 ] && [ -n "$DEV_IDS" ]; then
    APP_DEV=Build/DeviceData/Build/Products/Release-iphoneos/NeonGetaway.app
    : > Logs/device_install.log
    for DEV_ID in $DEV_IDS; do
      echo "== $DEV_ID ==" >> Logs/device_install.log
      xcrun devicectl device install app --device "$DEV_ID" "$APP_DEV" >> Logs/device_install.log 2>&1
      DI=$?
      echo "device $DEV_ID install exit code: $DI" | tee -a "$SUMMARY"
      if [ $DI -eq 0 ]; then
        xcrun devicectl device process launch --device "$DEV_ID" --terminate-existing "$BUNDLE" > Logs/device_launch.log 2>&1
        echo "device $DEV_ID launch exit code: $? (fails if the phone is locked; open the app from the Home Screen instead)" | tee -a "$SUMMARY"
      else
        tail -n 3 Logs/device_install.log >> "$SUMMARY"
      fi
    done
  fi
fi

if [ "$MODE" = "testflight" ] && [ "$ST" -eq 0 ] && [ "$XB" -eq 0 ]; then
  # Archive a Release build and upload it to App Store Connect (TestFlight). Each upload needs a
  # higher build number: tools/build_number.txt holds the last one used and is bumped here.
  LAST_BUILD=$(cat tools/build_number.txt 2>/dev/null || echo 1)
  BUILD=$((LAST_BUILD + 1))
  echo "== TestFlight: archive + upload, version $(grep -m1 'MARKETING_VERSION' NeonGetaway.xcodeproj/project.pbxproj | sed -E 's/.*= (.*);/\1/') build $BUILD ==" | tee -a "$SUMMARY"
  rm -rf Build/NeonGetaway.xcarchive Build/Export
  # Signs and uploads with the App Store Connect API key (Xcode itself has no account signed in).
  # The key lives outside the repo: ../.appstoreconnect/AuthKey_<id>.p8
  ASC_KEY_FILE=$(ls ../.appstoreconnect/AuthKey_*.p8 2>/dev/null | head -n 1)
  ASC_AUTH=()
  if [ -n "$ASC_KEY_FILE" ]; then
    ASC_KEY_ID=$(basename "$ASC_KEY_FILE" .p8 | sed 's/AuthKey_//')
    ASC_AUTH=(-authenticationKeyPath "$PWD/$ASC_KEY_FILE" -authenticationKeyID "$ASC_KEY_ID"
              -authenticationKeyIssuerID "${ASC_ISSUER:-e68f3170-f3b3-42c1-a66a-c33b1455907e}")
    echo "signing with App Store Connect API key $ASC_KEY_ID" | tee -a "$SUMMARY"
  fi
  xcodebuild -project NeonGetaway.xcodeproj -scheme NeonGetaway -configuration Release \
    -destination "generic/platform=iOS" -archivePath Build/NeonGetaway.xcarchive \
    -allowProvisioningUpdates "${ASC_AUTH[@]}" DEVELOPMENT_TEAM=X6LZQ3FS36 CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$BUILD" archive > Logs/archive.log 2>&1
  AR=$?
  grep -E "(error|warning): " Logs/archive.log | grep -v "^ld: warning" | sort -u | head -n 30 >> "$SUMMARY"
  tail -n 2 Logs/archive.log >> "$SUMMARY"
  echo "archive exit code: $AR" | tee -a "$SUMMARY"
  if [ $AR -eq 0 ]; then
    echo "$BUILD" > tools/build_number.txt
    xcodebuild -exportArchive -archivePath Build/NeonGetaway.xcarchive \
      -exportOptionsPlist tools/ExportOptions.plist -exportPath Build/Export \
      -allowProvisioningUpdates "${ASC_AUTH[@]}" > Logs/upload.log 2>&1
    UP=$?
    grep -E "error|Error|EXPORT|Upload|upload" Logs/upload.log | sort -u | tail -n 30 >> "$SUMMARY"
    echo "upload exit code: $UP" | tee -a "$SUMMARY"
  fi
fi

echo "== done $(date) ==" >> "$SUMMARY"
touch Logs/check_finished
cat "$SUMMARY"
