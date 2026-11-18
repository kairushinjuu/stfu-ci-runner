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
bash -n project/android-aot/build_android_strict.sh
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
install -m 0644 "$so" "$app/src/main/jniLibs/arm64-v8a/libstfu.so"
python3 - <<'PY'
from pathlib import Path
p=Path('project/android-aot/android-app/app/build.gradle')
s=p.read_text()
assert "versionCode 1" in s
assert "applicationId 'org.stfu.nativeport'" in s
s=s.replace('versionCode 1','versionCode 6').replace('0.0.35-experimental','0.0.43-real-frame-presentation').replace("applicationId 'org.stfu.nativeport'","applicationId 'org.stfu.nativeport.renderstage43'")
p.write_text(s)
p=Path('project/android-aot/android-app/app/src/main/AndroidManifest.xml')
s=p.read_text().replace('android:name=".SetupActivity"','android:name="org.stfu.nativeport.SetupActivity"').replace('android:name=".GameActivity"','android:name="org.stfu.nativeport.GameActivity"').replace('STFU Native (experimental)','STFU Stage43 Native Render Test')
p.write_text(s)
PY
grep -q 'LaunchPreparation.prepareSilent' "$app/src/main/java/org/stfu/nativeport/SetupActivity.java"
grep -q 'importPackages' "$app/src/main/java/org/stfu/nativeport/OriginalSplitMediaImporter.java"
mkdir -p "$RUNNER_TEMP/stfu-java"
javac -d "$RUNNER_TEMP/stfu-java" "$app/src/main/java/org/stfu/nativeport/GameAssetImporter.java" "$app/src/main/java/org/stfu/nativeport/OriginalSplitMediaImporter.java" stfu-native/stage40-three-packages/OriginalPackageHostTest.java
javac -d "$RUNNER_TEMP/stfu-java" stfu-native/stage41-runtime/LaunchPreparation.java stfu-native/stage41-runtime/LaunchPreparationHostTest.java
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
install -m 0600 "$apk" "$STFU_PROTECTED_DIR/STFU_Stage43_Real_Frame_ARM64_Debug.apk"
echo success > "$STFU_PROTECTED_DIR/build-result.txt"
