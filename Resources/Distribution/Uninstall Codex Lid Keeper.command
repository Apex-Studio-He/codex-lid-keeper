#!/usr/bin/env bash
set -euo pipefail

distribution_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bundled_uninstaller="$distribution_dir/Codex Lid Keeper.app/Contents/Resources/Uninstall Codex Lid Keeper.command"
installed_uninstaller="/Applications/Codex Lid Keeper.app/Contents/Resources/Uninstall Codex Lid Keeper.command"

if [[ -x "$installed_uninstaller" ]]; then
  exec "$installed_uninstaller"
fi
if [[ -x "$bundled_uninstaller" ]]; then
  exec "$bundled_uninstaller"
fi

printf 'No complete Codex Lid Keeper installation was found.\n' >&2
printf '没有找到完整的 Codex Lid Keeper 安装组件。\n' >&2
exit 1
