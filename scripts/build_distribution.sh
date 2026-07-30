#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
info_plist="$project_dir/Resources/App/Info.plist"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$info_plist")"

release_dir="$project_dir/dist/releases"
stage_dir="$project_dir/dist/distribution-root"
app_source="$project_dir/dist/Codex Lid Keeper.app"
artifact_base="Codex-Lid-Keeper-v${version}-universal"
dmg_path="$release_dir/${artifact_base}.dmg"
checksum_path="$release_dir/SHA256SUMS"

cd "$project_dir"

printf 'Running non-privileged release checks...\n'
"$script_dir/build.sh"
/usr/bin/python3 "$script_dir/test_hooks_config.py"
/usr/bin/python3 "$script_dir/test_e2e.py" \
  --binary "$project_dir/.build/release/codex-lid-keeper"

printf '\nBuilding Universal application...\n'
"$script_dir/build_app.sh" --universal

/bin/rm -rf "$stage_dir"
/bin/mkdir -p "$stage_dir" "$release_dir"
/usr/bin/ditto "$app_source" "$stage_dir/Codex Lid Keeper.app"
/usr/bin/install -m 0755 \
  "$project_dir/Resources/Distribution/Install Codex Lid Keeper.command" \
  "$stage_dir/Install Codex Lid Keeper.command"
/usr/bin/install -m 0755 \
  "$project_dir/Resources/Distribution/Uninstall Codex Lid Keeper.command" \
  "$stage_dir/Uninstall Codex Lid Keeper.command"
/usr/bin/install -m 0644 \
  "$project_dir/Resources/Distribution/README.txt" \
  "$stage_dir/README.txt"

/bin/rm -f "$dmg_path" "$checksum_path"
/usr/bin/hdiutil create \
  -volname "Codex Lid Keeper $version" \
  -srcfolder "$stage_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$dmg_path" >/dev/null

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "$(basename "$dmg_path")" > "$checksum_path"
)

"$script_dir/verify_distribution.sh" "$release_dir"

printf '\nRelease artifacts:\n'
printf '  %s\n' "$dmg_path"
printf '  %s\n' "$checksum_path"
