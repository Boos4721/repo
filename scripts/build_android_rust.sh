#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the installed Android NDK directory}"
command -v cargo-ndk >/dev/null || { echo 'Install cargo-ndk: cargo install cargo-ndk --locked'; exit 1; }
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
cd "$project_root/rust"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -p 26 -o "$project_root/app/android/app/src/main/jniLibs" build --release --locked
