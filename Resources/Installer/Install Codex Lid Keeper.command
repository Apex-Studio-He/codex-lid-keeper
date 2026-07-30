#!/usr/bin/env bash
set -u

resource_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
installer="$resource_dir/Installer/install_components.sh"

printf '\nCodex Lid Keeper — Public Alpha installer / 公开测试版安装程序\n'
printf 'This build is ad-hoc signed and is not Apple-notarized.\n'
printf '当前安装包使用 ad-hoc 签名，尚未通过 Apple notarization。\n'
printf 'Review the safety guide before supervised closed-lid testing.\n'
printf '合盖测试前请先阅读安全说明，并确保电脑放在开阔、通风的桌面上。\n\n'

"$installer"
status=$?

if [[ "$status" -ne 0 ]]; then
  printf '\nInstallation failed (exit %s). / 安装失败（退出码 %s）。\n' \
    "$status" "$status" >&2
fi

if [[ -t 0 ]]; then
  printf '\nPress Return to close this window. / 按回车关闭窗口。'
  IFS= read -r _
fi
exit "$status"
