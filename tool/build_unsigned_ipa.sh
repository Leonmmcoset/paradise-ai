#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'An iOS build requires macOS and Xcode.' >&2
  exit 1
fi

# --no-codesign skips signing and App Store export. Package the device .app
# ourselves because xcodebuild -exportArchive requires signing credentials.
flutter build ios --release --no-codesign
app='build/ios/iphoneos/Runner.app'
[[ -f "$app/Runner" ]] || { echo "Missing $app/Runner" >&2; exit 1; }
xcrun lipo -verify_arch arm64 "$app/Runner"
if [[ -d "$app/_CodeSignature" || -f "$app/embedded.mobileprovision" ]]; then
  echo 'Expected an unsigned application without a provisioning profile.' >&2
  exit 1
fi
if ! find "$app/Frameworks" -iname '*oii_bridge*' -print -quit | /usr/bin/grep -q .; then
  echo 'The OII native framework is missing from the application.' >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")
mkdir -p build/ios/ipa
ipa="$PWD/build/ios/ipa/paradise-$version-ios-unsigned.ipa"
staging=$(mktemp -d "$PWD/build/ios/ipa/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"

# A debug simulator run cannot detect release-only symbol stripping. These
# libraries are looked up by Dart FFI, so verify the shipped exports too.
symbols="$staging/native-symbols.txt"
xcrun nm -gU "$app/Runner" > "$symbols"
for framework in "$app"/Frameworks/*.framework; do
  case "$framework" in
    *typst_flutter*|*oii_bridge*|*ratex*|*RaTeX*)
      executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")
      xcrun lipo -verify_arch arm64 "$framework/$executable"
      xcrun nm -gU "$framework/$executable" >> "$symbols"
      ;;
  esac
done
for symbol in oii_bridge_engine_new oii_bridge_backup_validate frb_get_rust_content_hash frb_pde_ffi_dispatcher_primary ratex_parse_and_layout ratex_free_display_list ratex_get_last_error; do
  if ! /usr/bin/grep -Eq "[[:space:]]_${symbol}$" "$symbols"; then
    echo "Missing release FFI export: $symbol" >&2
    exit 1
  fi
done

ditto "$app" "$staging/Payload/Runner.app"
rm -f "$ipa"
ditto -c -k --keepParent --norsrc "$staging/Payload" "$ipa"
unzip -tq "$ipa"
echo "Unsigned IPA: $ipa"
