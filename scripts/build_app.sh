#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
app_dir="$project_dir/dist/Codex Lid Keeper.app"
contents_dir="$app_dir/Contents"
iconset_dir="$project_dir/.build/CodexLidKeeper.iconset"
icon_source="$project_dir/Resources/App/AppIcon.png"
build_mode="${1:-native}"

if [[ "$build_mode" != "native" && "$build_mode" != "--universal" ]]; then
  printf 'Usage: %s [--universal]\n' "$0" >&2
  exit 64
fi

cd "$project_dir"

if [[ "$build_mode" == "--universal" ]]; then
  for architecture in arm64 x86_64; do
    triple="${architecture}-apple-macosx13.0"
    build_path=".build/universal-${architecture}"
    swift build -c release -Xswiftc -warnings-as-errors \
      --triple "$triple" \
      --build-path "$build_path" \
      --product codex-lid-keeper
    swift build -c release -Xswiftc -warnings-as-errors \
      --triple "$triple" \
      --build-path "$build_path" \
      --product codex-lid-keeper-app
  done

  arm_release=".build/universal-arm64/arm64-apple-macosx/release"
  intel_release=".build/universal-x86_64/x86_64-apple-macosx/release"
else
  swift build -c release -Xswiftc -warnings-as-errors \
    --product codex-lid-keeper
  swift build -c release -Xswiftc -warnings-as-errors \
    --product codex-lid-keeper-app
fi

rm -rf "$app_dir" "$iconset_dir"
mkdir -p \
  "$contents_dir/MacOS" \
  "$contents_dir/Resources/Installer" \
  "$iconset_dir"

if [[ "$build_mode" == "--universal" ]]; then
  /usr/bin/lipo -create \
    "$arm_release/codex-lid-keeper-app" \
    "$intel_release/codex-lid-keeper-app" \
    -output "$contents_dir/MacOS/Codex Lid Keeper"
  /usr/bin/lipo -create \
    "$arm_release/codex-lid-keeper" \
    "$intel_release/codex-lid-keeper" \
    -output "$contents_dir/Resources/codex-lid-keeper"
  /bin/chmod 0755 \
    "$contents_dir/MacOS/Codex Lid Keeper" \
    "$contents_dir/Resources/codex-lid-keeper"
else
  /usr/bin/install -m 0755 \
    ".build/release/codex-lid-keeper-app" \
    "$contents_dir/MacOS/Codex Lid Keeper"
  /usr/bin/install -m 0755 \
    ".build/release/codex-lid-keeper" \
    "$contents_dir/Resources/codex-lid-keeper"
fi
/usr/bin/install -m 0755 \
  "scripts/install_components.sh" \
  "$contents_dir/Resources/Installer/install_components.sh"
/usr/bin/install -m 0755 \
  "scripts/uninstall_components.sh" \
  "$contents_dir/Resources/Installer/uninstall_components.sh"
/usr/bin/install -m 0755 \
  "scripts/preflight_hooks.sh" \
  "$contents_dir/Resources/Installer/preflight_hooks.sh"
/usr/bin/install -m 0755 \
  "scripts/emergency-restore.sh" \
  "$contents_dir/Resources/Installer/emergency-restore.sh"
/usr/bin/install -m 0755 \
  "Resources/Installer/Install Codex Lid Keeper.command" \
  "$contents_dir/Resources/Install Codex Lid Keeper.command"
/usr/bin/install -m 0755 \
  "Resources/Installer/Uninstall Codex Lid Keeper.command" \
  "$contents_dir/Resources/Uninstall Codex Lid Keeper.command"
/usr/bin/install -m 0644 \
  "Resources/com.zundu.codex-lid-keeper.agent.plist" \
  "$contents_dir/Resources/Installer/com.zundu.codex-lid-keeper.agent.plist"
/usr/bin/install -m 0644 \
  "Resources/com.zundu.codex-lid-keeper.recovery.plist" \
  "$contents_dir/Resources/Installer/com.zundu.codex-lid-keeper.recovery.plist"
/usr/bin/install -m 0644 \
  "Resources/App/Info.plist" \
  "$contents_dir/Info.plist"

for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  /usr/bin/sips -z "$size" "$size" "$icon_source" \
    --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$double_size" "$double_size" "$icon_source" \
    --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset_dir" \
  -o "$contents_dir/Resources/AppIcon.icns"

/usr/bin/plutil -lint "$contents_dir/Info.plist" >/dev/null
/usr/bin/codesign --force --options runtime --timestamp=none --sign - \
  "$contents_dir/Resources/codex-lid-keeper"
/usr/bin/codesign --force --options runtime --timestamp=none --sign - \
  "$contents_dir/MacOS/Codex Lid Keeper"
/usr/bin/codesign --force --options runtime --timestamp=none --sign - \
  "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

printf 'Built %s (%s)\n' "$app_dir" \
  "$([[ "$build_mode" == "--universal" ]] && printf 'Universal' || printf 'native')"
