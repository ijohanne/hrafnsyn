#!/usr/bin/env fish
set -l repo (path resolve (path dirname (status filename))/../..)
if test (count $argv) -ne 1
    echo 'Usage: test-ios.fish SIMULATOR_UDID' >&2
    exit 2
end
for variable in SDKROOT CC CXX LD LDPLUSPLUS AR AS NM RANLIB STRIP
    set -e $variable
end
set -gx PATH /usr/bin /bin $PATH
/usr/bin/xcodebuild -project "$repo/mobile/ios/Hrafnsyn.xcodeproj" -scheme Hrafnsyn \
    -destination "platform=iOS Simulator,id=$argv[1]" -derivedDataPath "$repo/mobile/build" \
    CODE_SIGN_IDENTITY=- test
