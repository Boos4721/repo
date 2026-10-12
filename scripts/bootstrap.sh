#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/app"
# Run on the developer's machine with an already installed Flutter SDK.
flutter create --platforms=android,ios --org com.boosbattery --project-name ant_bms .
python3 "$project_root/scripts/platform_config.py"
flutter pub get
