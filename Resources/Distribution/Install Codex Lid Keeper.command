#!/usr/bin/env bash
set -euo pipefail

distribution_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
installer="$distribution_dir/Codex Lid Keeper.app/Contents/Resources/Install Codex Lid Keeper.command"

if [[ ! -x "$installer" ]]; then
  printf 'The app or its installer is missing. Download the package again.\n' >&2
  printf 'App 或安装组件不完整，请重新下载安装包。\n' >&2
  exit 1
fi

exec "$installer"
