#!/usr/bin/env fish
# Apple SDK tools must handle the final iOS link, while dependencies come from Nix.
set -l repo (path resolve (path dirname (status filename))/../..)
for variable in SDKROOT CC CXX LD LDPLUSPLUS AR AS NM RANLIB STRIP
    set -e $variable
end
set -gx PATH /usr/bin /bin $PATH
/usr/bin/xcodebuild -project "$repo/mobile/ios/Hrafnsyn.xcodeproj" -scheme Hrafnsyn \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$repo/mobile/build" \
    CODE_SIGN_IDENTITY=- build $argv
