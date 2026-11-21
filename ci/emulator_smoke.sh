#!/usr/bin/env bash
# CI-only Stage57 Android emulator smoke. No proprietary media gets uploaded publicly.
# This is a launcher/native-ABI smoke, NOT full game playback without media.
set -Eeuo pipefail
umask 077
: "${ANDROID_SDK_ROOT:?}"
: "${STFU_PRIVATE_DIR:?}"
: "${STFU_PROTECTED_DIR:?}"
APP_APK="$STFU_PRIVATE_DIR/project/android-aot/android-app/app/build/outputs/apk/debug/app-debug.apk"
: "${STFU_EMULATOR_API:=35}"
APP_ID="org.stfu.nativeport.renderstage55"
OUT="$STFU_PROTECTED_DIR/emulator"
mkdir -p "$OUT"
[[ -s "$APP_APK" ]] || { echo "APK_NOT_BUILT"; exit 2; }
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
command -v sdkmanager >/dev/null
command -v adb >/dev/null
# Current official Google APIs x86_64 AVD images commonly provide ARM native bridge.
sdkmanager --install 'emulator' "system-images;android-${STFU_EMULATOR_API};google_apis;x86_64" > "$OUT/sdk-install.log" 2>&1
EMU_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
[[ -x "$EMU_BIN" ]]
AVD=stfu-stage57
# Use one explicit home for BOTH avdmanager and emulator. The previous CI
# run created an AVD that the emulator could not discover (Unknown AVD name).
export ANDROID_AVD_HOME="${RUNNER_TEMP:?}/stfu-stage57-avd-home"
mkdir -p "$ANDROID_AVD_HOME"
AVD_DIR="$ANDROID_AVD_HOME/$AVD.avd"
printf 'no\\n' | avdmanager create avd -n "$AVD" --path "$AVD_DIR" -k "system-images;android-${STFU_EMULATOR_API};google_apis;x86_64" --force > "$OUT/avd-create.log" 2>&1
avdmanager list avd -c > "$OUT/avd-list.txt" 2>&1
test -f "$ANDROID_AVD_HOME/$AVD.ini" || { echo 'AVD_INI_NOT_CREATED'; exit 7; }
test -f "$AVD_DIR/config.ini" || { echo 'AVD_CONFIG_NOT_CREATED'; exit 7; }
grep -Fxq "$AVD" "$OUT/avd-list.txt" || { echo 'AVDMANAGER_CANNOT_DISCOVER_AVD'; exit 7; }
"$EMU_BIN" -list-avds > "$OUT/emulator-avd-list.txt" 2>&1
grep -Fxq "$AVD" "$OUT/emulator-avd-list.txt" || { echo 'EMULATOR_CANNOT_DISCOVER_AVD'; exit 7; }
# Disable KVM only where truly absent; CPU fallback is slow and may time out.
ACCEL=off
if [[ -c /dev/kvm ]]; then
  if [[ ! -w /dev/kvm ]] && command -v sudo >/dev/null; then
    sudo chmod a+rw /dev/kvm || true
  fi
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then ACCEL=on; fi
fi
"$EMU_BIN" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -accel "$ACCEL" > "$OUT/emulator.log" 2>&1 &
EMU_PID=$!
cleanup(){ kill "$EMU_PID" 2>/dev/null || true; wait "$EMU_PID" 2>/dev/null || true; }
trap cleanup EXIT
adb start-server > "$OUT/adb-server.log" 2>&1
SERIAL=''
for i in $(seq 1 100); do
  SERIAL="$(adb devices | awk '$2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
  if [[ -n "$SERIAL" ]] && [[ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then break; fi
  sleep 6
done
if [[ -z "$SERIAL" || "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]]; then
  echo 'EMULATOR_BOOT_TIMEOUT'; exit 3
fi
{
  adb -s "$SERIAL" shell getprop ro.product.cpu.abilist
  adb -s "$SERIAL" shell getprop ro.dalvik.vm.native.bridge
  adb -s "$SERIAL" shell getprop ro.build.version.sdk
} > "$OUT/abi-and-bridge.txt"
if ! grep -q 'arm64-v8a' "$OUT/abi-and-bridge.txt"; then
  echo 'ARM64_NATIVE_BRIDGE_NOT_ADVERTISED'; exit 4
fi
adb -s "$SERIAL" install -r "$APP_APK" > "$OUT/install.txt" 2>&1
if ! grep -q 'Success' "$OUT/install.txt"; then echo 'APK_INSTALL_FAILED'; exit 5; fi
adb -s "$SERIAL" shell am start -W -n "$APP_ID/org.stfu.nativeport.SetupActivity" > "$OUT/launch.txt" 2>&1
sleep 6
adb -s "$SERIAL" shell pidof "$APP_ID" > "$OUT/pid.txt" 2>&1 || true
adb -s "$SERIAL" logcat -d -b main,crash -v threadtime > "$OUT/logcat.txt" 2>&1
adb -s "$SERIAL" shell screencap -p > "$OUT/setup-screen.png" 2>/dev/null || true
if [[ ! -s "$OUT/pid.txt" ]]; then echo 'SETUP_ACTIVITY_DIED'; exit 6; fi
echo 'PASS: ARM64 translation bridge advertised; signed STFU APK installs; SetupActivity alive.'
echo 'BLOCKED: Full audio-enabled gameplay requires original legally owned media securely provisioned into emulator.'