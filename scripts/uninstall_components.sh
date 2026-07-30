#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Codex Lid Keeper currently supports macOS only.\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bundled_binary="$(cd "$script_dir/.." && pwd -P)/codex-lid-keeper"
source_binary="$(cd "$script_dir/.." && pwd -P)/.build/release/codex-lid-keeper"
if [[ ! -x "$bundled_binary" && -x "$source_binary" ]]; then
  bundled_binary="$source_binary"
fi

binary_target="/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
app_target="/Applications/Codex Lid Keeper.app"
controller_binary="$app_target/Contents/Resources/codex-lid-keeper"
sudoers_target="/etc/sudoers.d/codex-lid-keeper"
daemon_target="/Library/LaunchDaemons/com.zundu.codex-lid-keeper.recovery.plist"
agent_target="${HOME:?}/Library/LaunchAgents/com.zundu.codex-lid-keeper.agent.plist"
ownership_file="/var/db/com.zundu.codex-lid-keeper.power.json"
hooks_file="${HOME:?}/.codex/hooks.json"
hook_command="$binary_target hook"
console_user="$(id -un)"
console_group="$(id -gn)"
console_uid="$(id -u)"

if [[ "$console_uid" == "0" ]] \
  || [[ ! "$console_user" =~ ^[A-Za-z0-9_.-]+$ ]] \
  || [[ ! "$console_group" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  printf 'Run this uninstaller from the macOS account that runs Codex, not as root.\n' >&2
  exit 1
fi

if ! active_console_user="$(/usr/bin/stat -f '%Su' /dev/console)" \
  || [[ "$active_console_user" != "$console_user" ]]; then
  printf 'Run this uninstaller from the currently logged-in macOS desktop account (%s).\n' \
    "${active_console_user:-unknown}" >&2
  exit 1
fi

/usr/bin/pkill -x "Codex Lid Keeper" >/dev/null 2>&1 || true

if [[ -x "$app_target/Contents/MacOS/Codex Lid Keeper" ]]; then
  if ! "$app_target/Contents/MacOS/Codex Lid Keeper" \
    --unregister-login-item >/dev/null; then
    printf 'Could not remove the login item; no files were deleted. Disable it in System Settings > General > Login Items, then retry.\n' >&2
    printf '无法移除登录项，尚未删除任何文件。请先到“系统设置 > 通用 > 登录项”中关闭它，再重试。\n' >&2
    exit 1
  fi
fi

printf 'Administrator access is required to restore and remove system components.\n'
/usr/bin/sudo -v

/bin/launchctl bootout \
  "gui/$console_uid/com.zundu.codex-lid-keeper.agent" >/dev/null 2>&1 || true
/bin/rm -f "$agent_target"

state_tool="$controller_binary"
if [[ ! -x "$state_tool" ]]; then
  state_tool="$bundled_binary"
fi
if [[ ! -x "$state_tool" ]]; then
  state_tool="$binary_target"
fi
if [[ -x "$state_tool" ]]; then
  "$state_tool" emergency-restore || true
fi

ownership_exists=0
if /usr/bin/sudo /bin/test -f "$ownership_file"; then
  ownership_exists=1
fi

restore_tool=""
if [[ -x "$binary_target" ]]; then
  restore_tool="$binary_target"
elif [[ "$ownership_exists" == "1" && -x "$controller_binary" ]]; then
  restore_tool="$controller_binary"
elif [[ "$ownership_exists" == "1" && -x "$bundled_binary" ]]; then
  restore_tool="$bundled_binary"
fi

if [[ "$ownership_exists" == "1" && -z "$restore_tool" ]]; then
  printf 'Power ownership exists, but no trusted CLI is available to restore it; refusing to remove recovery components.\n' >&2
  exit 1
fi
if [[ -n "$restore_tool" ]]; then
  /usr/bin/sudo "$restore_tool" power restore
fi
if /usr/bin/sudo /bin/test -f "$ownership_file"; then
  printf 'The power ownership record still exists after restore; refusing to continue.\n' >&2
  exit 1
fi

hook_tool="$controller_binary"
if [[ ! -x "$hook_tool" ]]; then
  hook_tool="$bundled_binary"
fi
if [[ ! -x "$hook_tool" ]]; then
  hook_tool="$binary_target"
fi
if [[ ! -x "$hook_tool" ]]; then
  printf 'Native Hook cleanup component is missing.\n' >&2
  exit 1
fi
"$hook_tool" hooks remove \
  --file "$hooks_file" \
  --command "$hook_command"

/usr/bin/sudo /bin/launchctl bootout \
  system/com.zundu.codex-lid-keeper.recovery >/dev/null 2>&1 || true
/usr/bin/sudo /bin/rm -f "$daemon_target"
/usr/bin/sudo /bin/rm -f "$sudoers_target"
/usr/bin/sudo /bin/rm -f "$binary_target"
/usr/bin/sudo /bin/rm -rf "$app_target"

printf '\nCodex Lid Keeper was uninstalled and its owned power state was restored.\n'
printf 'Codex Lid Keeper 已卸载，并已恢复由本项目接管的电源状态。\n'
printf 'User logs/config were preserved at: %s\n' \
  "${HOME:?}/Library/Application Support/CodexLidKeeper"
