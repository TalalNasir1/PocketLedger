#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/build"
app_dir="$build_dir/Pocket Ledger.app"
module_cache="$build_dir/module-cache"

mkdir -p "$build_dir" "$module_cache"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

build_arch() {
  local architecture="$1"
  local output="$build_dir/PocketLedger-$architecture"
  mkdir -p "$module_cache/$architecture"
  xcrun swiftc \
    -swift-version 5 \
    -target "$architecture-apple-macosx14.0" \
    -module-cache-path "$module_cache/$architecture" \
    -parse-as-library \
    "$project_dir"/Sources/*.swift \
    -o "$output" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Charts \
    -framework UserNotifications \
    -framework LocalAuthentication \
    -framework Security
}

build_arch arm64
build_arch x86_64
lipo -create "$build_dir/PocketLedger-arm64" "$build_dir/PocketLedger-x86_64" \
  -output "$app_dir/Contents/MacOS/PocketLedger"

cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
  cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$app_dir"
echo "Built: $app_dir"
