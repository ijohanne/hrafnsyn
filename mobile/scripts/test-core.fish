#!/usr/bin/env fish
# Uses the repository-local Rust toolchain installed by build-core.fish.
set -l repo (path resolve (path dirname (status filename))/../..)
set -gx RUSTUP_HOME "$repo/mobile/.toolchains/rustup"
set -l toolchain "$RUSTUP_HOME/toolchains/stable-aarch64-apple-darwin/bin"
if not test -x "$toolchain/cargo"
    echo 'Run nix develop -c fish mobile/scripts/build-core.fish first.' >&2
    exit 1
end
set -gx PATH "$toolchain" /usr/bin /bin $PATH
set -e SDKROOT
set -gx CC /usr/bin/clang
set -gx CXX /usr/bin/clang++
cd "$repo/mobile/core"; or exit 1
cargo test --locked --lib; or exit 1
if test (count $argv) -gt 0
    cargo run --locked --example smoke -- $argv[1]
end
