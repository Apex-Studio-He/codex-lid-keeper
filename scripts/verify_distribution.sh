#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
release_dir="${1:-$project_dir/dist/releases}"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
  "$project_dir/Resources/App/Info.plist")"
artifact_base="Codex-Lid-Keeper-v${version}-universal"
dmg_path="$release_dir/${artifact_base}.dmg"
checksum_path="$release_dir/SHA256SUMS"

if [[ ! -f "$dmg_path" || ! -f "$checksum_path" ]]; then
  printf 'Expected release artifacts were not found in %s\n' "$release_dir" >&2
  exit 1
fi

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 -c "$(basename "$checksum_path")"
)
/usr/bin/hdiutil verify "$dmg_path" >/dev/null

temporary_dir="$(mktemp -d /tmp/codex-lid-keeper-verify.XXXXXX)"
mount_dir="$temporary_dir/mount"
hooks_file="$temporary_dir/hooks.json"
mounted=0
cleanup() {
  if [[ "$mounted" == "1" ]]; then
    /usr/bin/hdiutil detach "$mount_dir" -quiet || true
  fi
  /bin/rm -rf "$temporary_dir"
}
trap cleanup EXIT

/bin/mkdir -p "$mount_dir"
/usr/bin/hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$mount_dir" \
  "$dmg_path" >/dev/null
mounted=1

app="$mount_dir/Codex Lid Keeper.app"
gui_binary="$app/Contents/MacOS/Codex Lid Keeper"
cli_binary="$app/Contents/Resources/codex-lid-keeper"
installer="$mount_dir/Install Codex Lid Keeper.command"
uninstaller="$mount_dir/Uninstall Codex Lid Keeper.command"

required_paths=(
  "$app/Contents/Info.plist"
  "$gui_binary"
  "$cli_binary"
  "$installer"
  "$uninstaller"
  "$mount_dir/README.txt"
  "$app/Contents/Resources/Install Codex Lid Keeper.command"
  "$app/Contents/Resources/Uninstall Codex Lid Keeper.command"
  "$app/Contents/Resources/Installer/install_components.sh"
  "$app/Contents/Resources/Installer/uninstall_components.sh"
  "$app/Contents/Resources/Installer/preflight_hooks.sh"
  "$app/Contents/Resources/Installer/emergency-restore.sh"
  "$app/Contents/Resources/Installer/com.zundu.codex-lid-keeper.agent.plist"
  "$app/Contents/Resources/Installer/com.zundu.codex-lid-keeper.recovery.plist"
)
for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    printf 'Distribution component is missing: %s\n' "$required_path" >&2
    exit 1
  fi
done

required_executables=(
  "$gui_binary"
  "$cli_binary"
  "$installer"
  "$uninstaller"
  "$app/Contents/Resources/Install Codex Lid Keeper.command"
  "$app/Contents/Resources/Uninstall Codex Lid Keeper.command"
  "$app/Contents/Resources/Installer/install_components.sh"
  "$app/Contents/Resources/Installer/uninstall_components.sh"
  "$app/Contents/Resources/Installer/preflight_hooks.sh"
  "$app/Contents/Resources/Installer/emergency-restore.sh"
)
for required_executable in "${required_executables[@]}"; do
  if [[ ! -x "$required_executable" ]]; then
    printf 'Distribution component is not executable: %s\n' \
      "$required_executable" >&2
    exit 1
  fi
done

for binary in "$gui_binary" "$cli_binary"; do
  arches="$(/usr/bin/lipo -archs "$binary")"
  if [[ " $arches " != *" arm64 "* || " $arches " != *" x86_64 "* ]]; then
    printf 'Binary is not Universal: %s (%s)\n' "$binary" "$arches" >&2
    exit 1
  fi
done

/usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
bundle_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
  "$app/Contents/Info.plist")"
if [[ "$bundle_version" != "$version" ]]; then
  printf 'Bundle version mismatch: expected %s, got %s\n' \
    "$version" "$bundle_version" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$app"
for binary in "$gui_binary" "$cli_binary"; do
  for arch in arm64 x86_64; do
    signature_details="$(
      /usr/bin/codesign -d --verbose=4 --arch "$arch" "$binary" 2>&1
    )"
    if [[ "$signature_details" != *"runtime"* ]]; then
      printf 'Hardened Runtime flag is missing: %s (%s)\n' \
        "$binary" "$arch" >&2
      exit 1
    fi
  done
done

/usr/bin/plutil -lint \
  "$app/Contents/Resources/Installer/com.zundu.codex-lid-keeper.agent.plist" \
  >/dev/null
/usr/bin/plutil -lint \
  "$app/Contents/Resources/Installer/com.zundu.codex-lid-keeper.recovery.plist" \
  >/dev/null

while IFS= read -r script; do
  /bin/bash -n "$script"
done < <(
  /usr/bin/find "$mount_dir" \
    \( -name '*.sh' -o -name '*.command' \) \
    -type f \
    -print
)

if /usr/bin/find "$app" -type f -name '*.py' -print -quit \
  | /usr/bin/grep -q .; then
  printf 'Release application unexpectedly contains a Python dependency.\n' >&2
  exit 1
fi

"$cli_binary" hooks install \
  --file "$hooks_file" \
  --command "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook" \
  >/dev/null
"$cli_binary" hooks verify \
  --file "$hooks_file" \
  --command "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook" \
  >/dev/null
"$cli_binary" hooks remove \
  --file "$hooks_file" \
  --command "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook" \
  >/dev/null

if /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  /usr/bin/arch -x86_64 "$cli_binary" help >/dev/null
fi

/usr/bin/grep -q 'notarized' "$mount_dir/README.txt"
/usr/bin/grep -q 'Never put a running, closed MacBook' "$mount_dir/README.txt"

printf 'Verified Universal DMG, app signature, native Hooks setup, and safety copy.\n'
