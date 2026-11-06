#!/usr/bin/env fish
set -l repo (path resolve (path dirname (status filename))/../..)
set -l sdk "$repo/mobile/android/.sdk"
if set -q HRAFNSYN_ANDROID_SDK
    set sdk "$HRAFNSYN_ANDROID_SDK"
else if not test -d "$sdk/ndk"
    set sdk "$ANDROID_HOME"
end
set -l ndk "$sdk/ndk/28.2.13676358"
if not test -d "$ndk"
    echo 'Install Android NDK 28.2.13676358; see mobile/android/README.md.' >&2
    exit 1
end
set -gx RUSTUP_HOME "$repo/mobile/.toolchains/rustup"
set -l rustbin "$RUSTUP_HOME/toolchains/stable-aarch64-apple-darwin/bin"
if not test -x "$rustbin/cargo"
    nix shell nixpkgs#rustup -c rustup toolchain install stable --profile minimal
    or exit 1
end
nix shell nixpkgs#rustup -c rustup target add aarch64-linux-android x86_64-linux-android --toolchain stable
or exit 1
set -l llvm "$ndk/toolchains/llvm/prebuilt/darwin-x86_64/bin"
set -gx PATH "$rustbin" "$llvm" /usr/bin /bin $PATH
for variable in SDKROOT CC CXX LD LDPLUSPLUS AR AS NM RANLIB STRIP
    set -e $variable
end
set -gx CC_aarch64_linux_android "$llvm/aarch64-linux-android26-clang"
set -gx AR_aarch64_linux_android "$llvm/llvm-ar"
set -gx CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER "$llvm/aarch64-linux-android26-clang"
set -gx CC_x86_64_linux_android "$llvm/x86_64-linux-android26-clang"
set -gx AR_x86_64_linux_android "$llvm/llvm-ar"
set -gx CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER "$llvm/x86_64-linux-android26-clang"
set -gx RUSTFLAGS '-C link-arg=-Wl,-z,max-page-size=16384'
cd "$repo/mobile/core"; or exit 1
for target in aarch64-linux-android x86_64-linux-android
    cargo build --locked --release --target "$target"; or exit 1
end
mkdir -p "$repo/mobile/android/app/src/main/jniLibs/arm64-v8a" "$repo/mobile/android/app/src/main/jniLibs/x86_64"
cp target/aarch64-linux-android/release/libhrafnsyn_mobile.so "$repo/mobile/android/app/src/main/jniLibs/arm64-v8a/"
cp target/x86_64-linux-android/release/libhrafnsyn_mobile.so "$repo/mobile/android/app/src/main/jniLibs/x86_64/"
