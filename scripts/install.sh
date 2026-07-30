#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
app_source="$project_dir/dist/Codex Lid Keeper.app"

printf 'Building and running non-privileged self-tests...\n'
"$script_dir/build.sh"
"$script_dir/build_app.sh"

"$app_source/Contents/Resources/Installer/install_components.sh" \
  "$app_source" \
  "$app_source/Contents/Resources"
