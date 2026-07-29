#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
app_dir="$project_dir/dist/Codex Lid Keeper.app"
contents_dir="$app_dir/Contents"
iconset_dir="$project_dir/.build/CodexLidKeeper.iconset"
icon_source="$project_dir/Resources/App/AppIcon.png"

cd "$project_dir"
swift build -c release -Xswiftc -warnings-as-errors \
  --product codex-lid-keeper
swift build -c release -Xswiftc -warnings-as-errors \
  --product codex-lid-keeper-app

rm -rf "$app_dir" "$iconset_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$iconset_dir"

/usr/bin/install -m 0755 \
  ".build/release/codex-lid-keeper-app" \
  "$contents_dir/MacOS/Codex Lid Keeper"
/usr/bin/install -m 0755 \
  ".build/release/codex-lid-keeper" \
  "$contents_dir/Resources/codex-lid-keeper"
/usr/bin/install -m 0755 \
  "scripts/hooks_config.py" \
  "$contents_dir/Resources/hooks_config.py"
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
/usr/bin/codesign --force --deep --sign - "$app_dir"

printf 'Built %s\n' "$app_dir"
