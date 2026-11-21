#!/usr/bin/env bash
# Runs exclusively inside an ephemeral, trusted GitHub-hosted runner.
# Never prints proprietary source, raw compiler diagnostics, secrets, game data or APK bytes to public logs.
set -Eeuo pipefail
umask 077
: "${STFU_PRIVATE_DIR:?private checkout required}"
: "${STFU_PROTECTED_DIR:?protected output directory required}"
: "${ANDROID_SDK_ROOT:?official Android SDK required}"
mkdir -p "$STFU_PROTECTED_DIR"
cd "$STFU_PRIVATE_DIR"
cat stfu-native/source-chunks/part*.bin > "$RUNNER_TEMP/stfu-private-source.zip"
printf '%s  %s\n' 'dac686aed30110b0012a4422b2f4a0a79528694e00fd9edfd8ee2c87f257f6ac' "$RUNNER_TEMP/stfu-private-source.zip" | sha256sum -c -
unzip -q "$RUNNER_TEMP/stfu-private-source.zip" -d .
test "$(find project/src/gen/sttng -maxdepth 1 -type f -name 'gen_*.c' | wc -l)" -eq 108
cp stfu-native/stage43-render/headless_smoke_native.c project/android-aot/headless_smoke_native.c
# Stage46 diagnostics attach to REAL native window/guest execution paths.
overlay=stfu-native/stage46-debug
for file in stfu_diag.h native_window_blit.c native_activity_shell.c android_game_entry.c android_runtime_logging.c; do
  test -s "$overlay/$file"
  install -m 0644 "$overlay/$file" "project/android-aot/$file"
done
grep -q 'stfu_diag_event' project/android-aot/native_window_blit.c
# Stage48: heartbeat in the native looper, separate real-time Android Dialog.
test -s stfu-native/stage48-debug/native_activity_shell.c
install -m 0644 stfu-native/stage48-debug/native_activity_shell.c project/android-aot/native_activity_shell.c
# Stage49: screenshot+export proved Android selected RGB_565 (4).
# Stage46 silently skipped drawing all 620 buffers due to RGBA_8888-only branch.
# Keep real game framebuffer, support RGB_565 and RGBA_8888, count actual pixels.
install -m 0644 stfu-native/stage49-render/native_window_blit.c project/android-aot/native_window_blit.c
grep -q 'STFU_RGB_565 4' project/android-aot/native_window_blit.c
grep -q 'frame_pixels_presented' project/android-aot/native_window_blit.c
grep -q 'looper_heartbeat' project/android-aot/native_activity_shell.c


grep -q 'STFU_ANDROID_GUEST_PRESENT_ATTEMPT' project/android-aot/headless_smoke_native.c
grep -q 'video_present(0)' project/android-aot/headless_smoke_native.c
python3 - <<'PY'
from pathlib import Path
p=Path('project/android-aot/build_android_strict.sh')
s=p.read_text()
old='"$TOOL/llvm-nm" -D "$OUT/libstfu.so" | grep -q \'ANativeActivity_onCreate\''
new='"$TOOL/llvm-nm" -D "$OUT/libstfu.so" > "$OUT/exported-symbols.txt"\ngrep -q \'ANativeActivity_onCreate\' "$OUT/exported-symbols.txt"'
assert s.count(old)==1, 'Refusing unknown strict build script format'
p.write_text(s.replace(old,new))
PY
# Experimental SOS software mixer and Android AAudio. Silent mode remains default.
# Fail closed if recovered stubs or strict NDK script do not match expected source.
STFU_STAGE47_EXPERIMENTAL_AUDIO=I_UNDERSTAND_EXPERIMENTAL bash stfu-native/stage47-audio-research/enable_aaudio_experiment.sh
# Stage57: correct undefined signed-left-shift of negative unsigned PCM bytes.
# Source-faithful mathematical conversion, independent host ASan/UBSan and
# nonzero PCM stereo regression. These are real mixer samples, not playback
# from the game's original audio assets. Preserve original HMI fail-closed.
audio=stfu-native/stage57-audio-emulator
test -s "$audio/native_sound_aaudio.c"
install -m 0644 "$audio/native_sound_aaudio.c" project/android-aot/native_sound_aaudio.c
! grep -Fq '(p[0] - 128) << 8' project/android-aot/native_sound_aaudio.c
gcc -std=c11 -Wall -Wextra -Werror -O1 -fsanitize=address,undefined -g \
  -I"$audio/stubs" -Iproject/src/rt -Iproject/android-aot \
  "$audio/audio_mixer_host_test.c" -lm -lpthread -o "$RUNNER_TEMP/stfu-stage57-audio-host"
UBSAN_OPTIONS=halt_on_error=1 ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
  "$RUNNER_TEMP/stfu-stage57-audio-host" > "$STFU_PROTECTED_DIR/stage57-audio-host-test.txt"
grep -q STAGE57_AAUDIO_PCM_MIXER_PASS "$STFU_PROTECTED_DIR/stage57-audio-host-test.txt"
# Stage52 private fatal-reason capture (unchanged termination semantics).
# Records the actual translated guest runtime error in the existing exported
# diagnostics log. Keep the proven Stage49 RGB565 renderer byte-identical.
test -s stfu-native/stage52-diagnostics/android_runtime_logging.c
install -m 0644 stfu-native/stage52-diagnostics/android_runtime_logging.c project/android-aot/android_runtime_logging.c
grep -q 'native_runtime_fatal: %s' project/android-aot/android_runtime_logging.c
# Stage53: source-derived guest module loader error diagnosis. This is a
# private-only replayable overlay; the original translated game branch, exit
# and renderer behavior are deliberately unchanged.
test -s stfu-native/stage53-static-trace/instrument_guest_startup.py
python3 stfu-native/stage53-static-trace/instrument_guest_startup.py project
grep -q 'resource-loader-failure' project/src/gen/sttng/gen_008.c
grep -q 'main-initialization-failure' project/src/gen/sttng/gen_001.c
# Stage51 private-only genuine guest input/controller overlay.
# This is an authenticated checkout; the public repo contains no game source.
control=stfu-native/stage51-control
for name in android_input_bridge.c android_input_bridge.h; do
  test -s "$control/$name"
  install -m 0644 "$control/$name" "project/android-aot/$name"
done
# Non-interfering host check: Java JNI -> native queue -> DOS input transitions.
gcc -std=c11 -O2 -Iproject/android-aot "$control/android_input_bridge.c"   "$control/ndk_input_stubs.c" "$control/control_queue_host_test.c"   -o "$RUNNER_TEMP/stfu-stage51-input-host"
"$RUNNER_TEMP/stfu-stage51-input-host" > "$STFU_PROTECTED_DIR/stage51-input-host-test.txt"
bash -n project/android-aot/build_android_strict.sh
grep -q -- '-laaudio' project/android-aot/build_android_strict.sh
grep -q -- 'native_sound_aaudio' project/android-aot/build_android_strict.sh

grep -q -- '--no-undefined' project/android-aot/build_android_strict.sh
export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/27.2.12479018"
test -x "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" --version > "$STFU_PROTECTED_DIR/ndk-version.txt"
printf '%s\n' "$(git rev-parse HEAD)" > "$STFU_PROTECTED_DIR/private-source-commit.txt"
(cd project && JOBS=3 bash android-aot/build_android_strict.sh)
so=project/android-aot/build-real-ndk/libstfu.so
test -s "$so"
file "$so" > "$STFU_PROTECTED_DIR/native-elf-file.txt"
readelf -h "$so" > "$STFU_PROTECTED_DIR/native-elf-header.txt"
grep -q -E 'Machine:.*AArch64' "$STFU_PROTECTED_DIR/native-elf-header.txt"
grep -q -E 'Type:.*DYN' "$STFU_PROTECTED_DIR/native-elf-header.txt"
nm -D "$so" > "$STFU_PROTECTED_DIR/native-exports.txt"
grep -q 'ANativeActivity_onCreate' "$STFU_PROTECTED_DIR/native-exports.txt"
sha256sum "$so" > "$STFU_PROTECTED_DIR/sha256-libstfu.txt"
app=project/android-aot/android-app/app
mkdir -p "$app/src/main/res/values" "$app/src/main/jniLibs/arm64-v8a"
cp stfu-native/stage38-ui/styles.xml "$app/src/main/res/values/styles.xml"
cp stfu-native/stage38-ui/AndroidManifest.xml "$app/src/main/AndroidManifest.xml"
cp stfu-native/stage39-original-media/GameAssetImporter.java "$app/src/main/java/org/stfu/nativeport/GameAssetImporter.java"
cp stfu-native/stage40-three-packages/OriginalSplitMediaImporter.java "$app/src/main/java/org/stfu/nativeport/OriginalSplitMediaImporter.java"
for name in SetupActivity.java GameActivity.java LaunchPreparation.java; do
  cp "stfu-native/stage41-runtime/$name" "$app/src/main/java/org/stfu/nativeport/$name"
done
# Stage46 debug overlay/export added to both NativeActivity and SetupActivity.
for file in GameActivity.java SetupActivity.java LaunchPreparation.java; do
  install -m 0644 "stfu-native/stage48-debug/$file" "$app/src/main/java/org/stfu/nativeport/$file"
done
# Stage54 proven gameplay-startup repair. Original STTNG.INI Path=C:\\STTNG\\,
# but earlier import staged all files at C:\\ root. Original title ->
# sosDIGIInitDriver resource error reproduced with flat install, but disappears
# with true C:\\STTNG directory and silent settings on authentic media host.
layout=stfu-native/stage55-ini-normalization
for name in DosLayoutPreparation.java LaunchPreparation.java DosLayoutPreparationHostTest.java; do
  test -s "$layout/$name"
done
mkdir -p "$RUNNER_TEMP/stfu54-classes"
javac -d "$RUNNER_TEMP/stfu54-classes" "$layout/DosLayoutPreparation.java" "$layout/LaunchPreparation.java" "$layout/DosLayoutPreparationHostTest.java"
java -cp "$RUNNER_TEMP/stfu54-classes" org.stfu.nativeport.DosLayoutPreparationHostTest > "$STFU_PROTECTED_DIR/stage54-dos-layout-host-test.txt"
grep -q STAGE54_DOS_LAYOUT_HOST_TEST_PASS "$STFU_PROTECTED_DIR/stage54-dos-layout-host-test.txt"
grep -q STAGE55_NO_PATH_HOST_TEST_PASS "$STFU_PROTECTED_DIR/stage54-dos-layout-host-test.txt"
install -m 0644 "$layout/DosLayoutPreparation.java" "$app/src/main/java/org/stfu/nativeport/DosLayoutPreparation.java"
install -m 0644 "$layout/LaunchPreparation.java" "$app/src/main/java/org/stfu/nativeport/LaunchPreparation.java"
grep -q 'DosLayoutPreparation.prepare(root)' "$app/src/main/java/org/stfu/nativeport/LaunchPreparation.java"
test -s "$control/GameActivity.java"
install -m 0644 "$control/GameActivity.java" "$app/src/main/java/org/stfu/nativeport/GameActivity.java"
grep -q 'nativeControl' "$app/src/main/java/org/stfu/nativeport/GameActivity.java"
grep -q 'new Dialog(this)' "$app/src/main/java/org/stfu/nativeport/GameActivity.java"
grep -q 'prepareExperimentalAudio' "$app/src/main/java/org/stfu/nativeport/SetupActivity.java"
install -m 0644 "$so" "$app/src/main/jniLibs/arm64-v8a/libstfu.so"
python3 - <<'PY'
from pathlib import Path
p=Path('project/android-aot/android-app/app/build.gradle')
s=p.read_text()
assert "versionCode 1" in s
assert "applicationId 'org.stfu.nativeport'" in s
s=s.replace('versionCode 1','versionCode 15').replace('0.0.35-experimental','0.0.55-ini-normalization').replace("applicationId 'org.stfu.nativeport'","applicationId 'org.stfu.nativeport.renderstage55'")
p.write_text(s)
p=Path('project/android-aot/android-app/app/src/main/AndroidManifest.xml')
s=p.read_text().replace('android:name=".SetupActivity"','android:name="org.stfu.nativeport.SetupActivity"').replace('android:name=".GameActivity"','android:name="org.stfu.nativeport.GameActivity"').replace('STFU Native (experimental)','STFU Stage55 INI Repair RGB565 Controls')
p.write_text(s)
PY
grep -q 'LaunchPreparation.prepareSilent' "$app/src/main/java/org/stfu/nativeport/SetupActivity.java"
grep -q 'importPackages' "$app/src/main/java/org/stfu/nativeport/OriginalSplitMediaImporter.java"
mkdir -p "$RUNNER_TEMP/stfu-java"
javac -d "$RUNNER_TEMP/stfu-java" "$app/src/main/java/org/stfu/nativeport/GameAssetImporter.java" "$app/src/main/java/org/stfu/nativeport/OriginalSplitMediaImporter.java" stfu-native/stage40-three-packages/OriginalPackageHostTest.java
javac -d "$RUNNER_TEMP/stfu-java" stfu-native/stage48-debug/LaunchPreparation.java stfu-native/stage41-runtime/LaunchPreparationHostTest.java
printf 'Audio=SBPRO\r\nSound=ON\r\nMusic=ON\r\nVoices=ON\r\n' > "$RUNNER_TEMP/STTNG.INI"
java -cp "$RUNNER_TEMP/stfu-java" org.stfu.nativeport.LaunchPreparationHostTest "$RUNNER_TEMP/STTNG.INI" > "$STFU_PROTECTED_DIR/silent-host-test.txt"
gradle --no-daemon -p project/android-aot/android-app :app:assembleDebug
apk="$app/build/outputs/apk/debug/app-debug.apk"
test -s "$apk"
unzip -t "$apk" > "$STFU_PROTECTED_DIR/apk-zip.txt"
unzip -p "$apk" lib/arm64-v8a/libstfu.so > "$RUNNER_TEMP/stfu-packaged.so"
cmp "$so" "$RUNNER_TEMP/stfu-packaged.so"
readelf -h "$RUNNER_TEMP/stfu-packaged.so" | grep -q -E 'Machine:.*AArch64'
"$ANDROID_SDK_ROOT/build-tools/35.0.0/apksigner" verify --verbose "$apk" > "$STFU_PROTECTED_DIR/apk-signing.txt"
grep -q 'Verified using v2 scheme (APK Signature Scheme v2): true' "$STFU_PROTECTED_DIR/apk-signing.txt"
sha256sum "$apk" > "$STFU_PROTECTED_DIR/sha256-apk.txt"
install -m 0600 "$apk" "$STFU_PROTECTED_DIR/STFU_Stage55_INI_Path_Repair_ARM64.apk"
echo success > "$STFU_PROTECTED_DIR/build-result.txt"
