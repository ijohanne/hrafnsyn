#!/usr/bin/env fish
set -l repo (path resolve (path dirname (status filename))/../..)
set -l sdk "$repo/mobile/android/.sdk"
if set -q HRAFNSYN_ANDROID_SDK
    set sdk "$HRAFNSYN_ANDROID_SDK"
else if not test -d "$sdk/platforms/android-36"
    set sdk "$ANDROID_HOME"
end
if not test -d "$sdk/platforms/android-36"
    echo 'Android SDK platform 36 is required; see mobile/android/README.md.' >&2
    exit 1
end
set -gx ANDROID_HOME "$sdk"
set -gx ANDROID_SDK_ROOT "$sdk"
if not set -q JAVA_HOME; or not test -x "$JAVA_HOME/bin/java"
    set -gx JAVA_HOME (path dirname (path dirname (path resolve (command -s java))))
end
if not test -f "$repo/mobile/android/app/src/main/jniLibs/arm64-v8a/libhrafnsyn_mobile.so"
    echo 'Run nix develop -c fish mobile/scripts/build-core-android.fish first.' >&2
    exit 1
end
cd "$repo/mobile/android"; or exit 1
if test (count $argv) -eq 0
    ./gradlew --no-daemon assembleDebug testDebugUnitTest
else
    ./gradlew --no-daemon $argv
end
