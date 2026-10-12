#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS + Xcode'; exit 1; }
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build --manifest-path "$project_root/rust/Cargo.toml" --release --locked --target "$target"
done
mkdir -p "$project_root/app/ios/Rust/iphoneos" "$project_root/app/ios/Rust/iphonesimulator" "$project_root/app/ios/Flutter"
cp "$project_root/rust/target/aarch64-apple-ios/release/libant_core.a" "$project_root/app/ios/Rust/iphoneos/"
lipo -create "$project_root/rust/target/aarch64-apple-ios-sim/release/libant_core.a" "$project_root/rust/target/x86_64-apple-ios/release/libant_core.a" -output "$project_root/app/ios/Rust/iphonesimulator/libant_core.a"
cat > "$project_root/app/ios/Flutter/Rust.xcconfig" <<'CONFIG'
OTHER_LDFLAGS = $(inherited) -force_load "$(SRCROOT)/Rust/$(PLATFORM_NAME)/libant_core.a" -Wl,-exported_symbol,_ant_engine_new -Wl,-exported_symbol,_ant_engine_free -Wl,-exported_symbol,_ant_engine_reset -Wl,-exported_symbol,_ant_engine_feed -Wl,-exported_symbol,_ant_string_free -Wl,-exported_symbol,_ant_read_request -Wl,-exported_symbol,_ant_demo_frame
CONFIG
python3 "$project_root/scripts/platform_config.py"
