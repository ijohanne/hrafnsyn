#!/usr/bin/env fish
# Usage: nix develop -c fish mobile/scripts/export-adhoc.fish TEAM_ID PROFILE_NAME [BUNDLE_ID]
if test (count $argv) -lt 2
    echo 'Usage: export-adhoc.fish TEAM_ID AD_HOC_PROFILE_NAME [BUNDLE_ID]' >&2
    exit 2
end
set -l team $argv[1]
set -l profile $argv[2]
set -l bundle io.hrafnsyn.mobile
if test (count $argv) -ge 3
    set bundle $argv[3]
end
set -l repo (path resolve (path dirname (status filename))/../..)
set -l output "$repo/mobile/build/ad-hoc"
mkdir -p "$output"
for variable in SDKROOT CC CXX LD LDPLUSPLUS AR AS NM RANLIB STRIP
    set -e $variable
end
set -gx PATH /usr/bin /bin $PATH
# Values are passed as argv, never interpolated into XML or shell source.
/usr/bin/plutil -create xml1 "$output/ExportOptions.plist"
or exit 1
/usr/bin/plutil -insert method -string release-testing "$output/ExportOptions.plist"
/usr/bin/plutil -insert teamID -string "$team" "$output/ExportOptions.plist"
/usr/bin/plutil -insert signingStyle -string manual "$output/ExportOptions.plist"
/usr/bin/plutil -insert signingCertificate -string 'Apple Distribution' "$output/ExportOptions.plist"
/usr/bin/plutil -insert provisioningProfiles -dictionary "$output/ExportOptions.plist"
# plutil's key paths escape dots; bundle IDs contain dots.
set -l escaped_bundle (string replace -a . '\\.' -- "$bundle")
/usr/bin/plutil -insert "provisioningProfiles.$escaped_bundle" -string "$profile" "$output/ExportOptions.plist"
or exit 1
/usr/bin/xcodebuild -project "$repo/mobile/ios/Hrafnsyn.xcodeproj" -scheme Hrafnsyn \
    -configuration Release -destination 'generic/platform=iOS' -archivePath "$output/Hrafnsyn.xcarchive" \
    DEVELOPMENT_TEAM="$team" PRODUCT_BUNDLE_IDENTIFIER="$bundle" CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER="$profile" archive
or exit 1
/usr/bin/xcodebuild -exportArchive -archivePath "$output/Hrafnsyn.xcarchive" \
    -exportPath "$output/export" -exportOptionsPlist "$output/ExportOptions.plist"
or exit 1
echo "IPA exported to $output/export"
