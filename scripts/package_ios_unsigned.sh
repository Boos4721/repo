#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS + Xcode; no IPA was generated.'; exit 1; }
command -v xcodebuild >/dev/null || { echo 'Install Xcode first'; exit 1; }
cd "$project_root/app"
flutter build ios --release --no-codesign
bundle="$project_root/app/build/ios/iphoneos/Runner.app"
[[ -d "$bundle" ]] || { echo 'Runner.app missing; no IPA generated'; exit 1; }
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist")"
[[ -f "$bundle/$executable" ]] || { echo 'App executable missing'; exit 1; }
xcrun lipo "$bundle/$executable" -verify_arch arm64
python3 "$project_root/scripts/verify_ios_symbols.py" "$bundle/$executable"
mkdir -p "$project_root/dist"
staging="$(mktemp -d "$project_root/dist/ipa-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"
ditto "$bundle" "$staging/Payload/Runner.app"
archive="$project_root/dist/ANT-BMS-unsigned.ipa"
# zip -y preserves framework symlinks; remove only this generated archive on rebuild.
rm -f "$archive"
(cd "$staging" && zip -qry "$archive" Payload)
unzip -tq "$archive"
printf 'Unsigned IPA generated: %s\n' "$archive"
printf 'This package must be signed before installing on an iPhone.\n'

