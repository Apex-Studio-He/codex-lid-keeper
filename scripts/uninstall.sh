#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installed_uninstaller="/Applications/Codex Lid Keeper.app/Contents/Resources/Installer/uninstall_components.sh"

if [[ -x "$installed_uninstaller" ]]; then
  exec "$installed_uninstaller"
fi

exec "$script_dir/uninstall_components.sh"
