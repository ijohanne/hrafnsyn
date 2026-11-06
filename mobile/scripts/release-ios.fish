#!/usr/bin/env fish
# Run from any working directory; Nix's shell hook must run in this repository.
set -l repo (path resolve (path dirname (status filename))/../..)
cd "$repo"; or exit 1
exec nix develop -c python3 "$repo/mobile/scripts/release_ios.py" $argv
