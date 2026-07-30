#!/usr/bin/env bash
set -u

resource_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
uninstaller="$resource_dir/Installer/uninstall_components.sh"

printf '\nCodex Lid Keeper uninstaller / 卸载程序\n'
printf 'Owned sleep state will be restored before components are removed.\n'
printf '卸载前会先恢复本项目接管的睡眠设置。\n\n'

"$uninstaller"
status=$?

if [[ "$status" -ne 0 ]]; then
  printf '\nUninstall failed (exit %s). / 卸载失败（退出码 %s）。\n' \
    "$status" "$status" >&2
fi

if [[ -t 0 ]]; then
  printf '\nPress Return to close this window. / 按回车关闭窗口。'
  IFS= read -r _
fi
exit "$status"
