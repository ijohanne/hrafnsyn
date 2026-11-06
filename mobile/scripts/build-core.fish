#!/usr/bin/env fish
# Run from the repository root inside `nix develop`.
set -l repo (path resolve (path dirname (status filename))/../..)
set -l mobile "$repo/mobile"
set -gx RUSTUP_HOME "$mobile/.toolchains/rustup"
set -l toolchain "$RUSTUP_HOME/toolchains/stable-aarch64-apple-darwin/bin"
if not test -x "$toolchain/cargo"
    nix shell nixpkgs#rustup -c rustup toolchain install stable --profile minimal --target aarch64-apple-ios,aarch64-apple-ios-sim
    or exit 1
end
# Apple's tools must precede Nix's SDK shims for iOS cross-compilation.
set -gx PATH "$toolchain" /usr/bin /bin $PATH
set -e SDKROOT
set -e DEVELOPER_DIR
set -gx CC /usr/bin/clang
set -gx CXX /usr/bin/clang++
set -gx CARGO_TARGET_AARCH64_APPLE_IOS_LINKER /usr/bin/clang
set -gx CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER /usr/bin/clang
set -gx IPHONEOS_DEPLOYMENT_TARGET 18.0
cd "$mobile/core"; or exit 1
cargo build --locked --features bindings; or exit 1
cargo run --locked --features bindings --bin uniffi-bindgen -- generate --library target/debug/libhrafnsyn_mobile.dylib --language swift --out-dir ../ios/Generated; or exit 1
cargo run --locked --features bindings --bin uniffi-bindgen -- generate --library target/debug/libhrafnsyn_mobile.dylib --language kotlin --out-dir ../android/generated --no-format; or exit 1
cp ../ios/Generated/HrafnsynCoreFFI.modulemap ../ios/Generated/module.modulemap; or exit 1
cargo build --locked --release --target aarch64-apple-ios; or exit 1
cargo build --locked --release --target aarch64-apple-ios-sim; or exit 1
set -l framework "$mobile/ios/Frameworks/HrafnsynCore.xcframework"
if test -d "$framework"
    rm -r "$framework"
end
mkdir -p "$mobile/ios/Frameworks"
/usr/bin/xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libhrafnsyn_mobile.a -headers ../ios/Generated \
    -library target/aarch64-apple-ios-sim/release/libhrafnsyn_mobile.a -headers ../ios/Generated \
    -output "$framework"
or exit 1
nix shell nixpkgs#xcodegen -c xcodegen generate --spec "$mobile/ios/project.yml"
