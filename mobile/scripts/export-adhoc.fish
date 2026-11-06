#!/usr/bin/env fish
# Usage: nix develop -c fish mobile/scripts/export-adhoc.fish [--sync-devices] TEAM_ID PROFILE_NAME [BUNDLE_ID]
argparse sync-devices 'devices-file=' 'output-dir=' 'associated-domains-file=' -- $argv; or exit 2
if test (count $argv) -lt 2; or test (count $argv) -gt 3
    echo 'Usage: export-adhoc.fish [--sync-devices] TEAM_ID AD_HOC_PROFILE_NAME [BUNDLE_ID]' >&2
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
if set -q _flag_output_dir
    set output (path resolve "$_flag_output_dir")
end
mkdir -p "$output"
set -l python (command -s python3)
set -l devices "$repo/mobile/signing/devices.txt"
if set -q HRAFNSYN_IOS_DEVICES_FILE
    set devices "$HRAFNSYN_IOS_DEVICES_FILE"
end
if set -q _flag_devices_file
    set devices "$_flag_devices_file"
end
set -l sync_args
set -l domain_args
if set -q _flag_associated_domains_file
    set domain_args --associated-domains-file (path resolve "$_flag_associated_domains_file")
end
if set -q _flag_sync_devices
    set sync_args --sync-devices
end
"$python" "$repo/mobile/scripts/ios_devices.py" prepare \
    --devices "$devices" --team "$team" --bundle "$bundle" --profile "$profile" \
    --output "$output" $sync_args $domain_args
or exit 1
# Use the exact validated UUID, not an ambiguous profile display name.
set profile (string trim (cat "$output/signing-profile.txt"))
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
    CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER="$profile" \
    CODE_SIGN_ENTITLEMENTS="$output/signing.entitlements" archive
or exit 1
/usr/bin/xcodebuild -exportArchive -archivePath "$output/Hrafnsyn.xcarchive" \
    -exportPath "$output/export" -exportOptionsPlist "$output/ExportOptions.plist"
or exit 1
set -l ipas "$output"/export/*.ipa
if test (count $ipas) -ne 1
    echo 'Expected exactly one exported IPA. Remove stale files from mobile/build/ad-hoc/export and retry.' >&2
    exit 1
end
"$python" "$repo/mobile/scripts/ios_devices.py" verify \
    --devices "$devices" --team "$team" --bundle "$bundle" --output "$output" --ipa "$ipas[1]" $domain_args
or exit 1
echo "IPA exported to $output/export"
