#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Codex Lid Keeper currently supports macOS only.\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
default_resources="$(cd "$script_dir/.." && pwd -P)"
resource_dir="${2:-$default_resources}"
default_app="$(cd "$resource_dir/../.." && pwd -P)"
app_source="${1:-$default_app}"

binary_source="$resource_dir/codex-lid-keeper"
agent_source="$resource_dir/Installer/com.zundu.codex-lid-keeper.agent.plist"
daemon_source="$resource_dir/Installer/com.zundu.codex-lid-keeper.recovery.plist"
preflight_script="$script_dir/preflight_hooks.sh"

binary_target="/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
app_target="/Applications/Codex Lid Keeper.app"
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
  printf 'Run this installer from the macOS account that runs Codex, not as root.\n' >&2
  exit 1
fi

required_files=(
  "$app_source/Contents/Info.plist"
  "$app_source/Contents/MacOS/Codex Lid Keeper"
  "$binary_source"
  "$agent_source"
  "$daemon_source"
  "$preflight_script"
)
for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'Install component is missing: %s\n' "$required_file" >&2
    exit 1
  fi
done

bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw \
  "$app_source/Contents/Info.plist")"
if [[ "$bundle_id" != "com.zundu.codex-lid-keeper.app" ]]; then
  printf 'Unexpected application identifier: %s\n' "$bundle_id" >&2
  exit 1
fi

/usr/bin/plutil -lint "$app_source/Contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$agent_source" >/dev/null
/usr/bin/plutil -lint "$daemon_source" >/dev/null
/usr/bin/codesign --verify --deep --strict "$app_source"

runtime_arch="$(uname -m)"
binary_arches="$(/usr/bin/lipo -archs "$binary_source")"
if [[ " $binary_arches " != *" $runtime_arch "* ]]; then
  printf 'The bundled helper does not support this Mac architecture (%s).\n' \
    "$runtime_arch" >&2
  exit 1
fi

stage_dir="$(mktemp -d /tmp/codex-lid-keeper-install.XXXXXX)"
app_stage="/Applications/.Codex Lid Keeper.app.installing.$console_uid"
cleanup() {
  /bin/rm -rf "$stage_dir"
}
trap cleanup EXIT

sudoers_stage="$stage_dir/codex-lid-keeper.sudoers"
printf '%s ALL=(root) NOPASSWD: %s power enable-ac, %s power enable-battery, %s power restore\n' \
  "$console_user" "$binary_target" "$binary_target" "$binary_target" \
  > "$sudoers_stage"
/bin/chmod 0440 "$sudoers_stage"

"$preflight_script" \
  "$binary_source" \
  "$hooks_file" \
  "$hook_command"

printf '\nCodex Lid Keeper needs administrator access for its fixed-function power helper.\n'
printf '管理员密码由 macOS 的标准 sudo 流程读取；App 不会看到或保存密码。\n\n'
/usr/bin/sudo -v

if ! /usr/bin/sudo /usr/bin/grep -Eq \
  '^[[:space:]]*([#@]includedir)[[:space:]]+/(private/)?etc/sudoers\.d' \
  /etc/sudoers; then
  printf '/etc/sudoers does not include /etc/sudoers.d; refusing a partial install.\n' >&2
  exit 1
fi
/usr/bin/sudo /usr/sbin/visudo -cf "$sudoers_stage" >/dev/null

user_agent_service="gui/$console_uid/com.zundu.codex-lid-keeper.agent"
recovery_service="system/com.zundu.codex-lid-keeper.recovery"

component_startup_failed() {
  local stage="$1"
  local cleanup_incomplete=0
  local user_agent_stopped=1
  local user_state_cleared=1
  local ownership_cleared=1
  local cleanup_controller=

  if /bin/launchctl print "$user_agent_service" >/dev/null 2>&1; then
    if ! /bin/launchctl bootout "$user_agent_service"; then
      cleanup_incomplete=1
      user_agent_stopped=0
    fi
  fi
  /bin/rm -f "$agent_target"

  if [[ "$user_agent_stopped" == "1" ]]; then
    cleanup_controller="$app_target/Contents/Resources/codex-lid-keeper"
    if [[ ! -x "$cleanup_controller" ]]; then
      cleanup_controller="$binary_source"
    fi
    if ! "$cleanup_controller" emergency-restore; then
      cleanup_incomplete=1
      user_state_cleared=0
    fi
    if /usr/bin/sudo /bin/test -f "$ownership_file"; then
      if ! /usr/bin/sudo "$binary_target" power restore; then
        cleanup_incomplete=1
        ownership_cleared=0
      fi
    fi
    if /usr/bin/sudo /bin/test -f "$ownership_file"; then
      cleanup_incomplete=1
      ownership_cleared=0
    fi
  else
    ownership_cleared=0
  fi

  if [[ "$user_agent_stopped" == "1"
        && "$user_state_cleared" == "1"
        && "$ownership_cleared" == "1" ]]; then
    if /usr/bin/sudo /bin/launchctl print \
      "$recovery_service" >/dev/null 2>&1; then
      if ! /usr/bin/sudo /bin/launchctl bootout "$recovery_service"; then
        cleanup_incomplete=1
      fi
    fi
  fi

  printf '\nSystem component startup failed at: %s\n' "$stage" >&2
  printf 'The App and fixed system files were kept so the same installer can repair them. No Hooks were added. Rerun “Install Codex Lid Keeper.command”.\n' >&2
  printf '系统组件在“%s”阶段启动失败。App 与固定系统文件已保留，且尚未写入 Hooks；请重新运行“Install Codex Lid Keeper.command”完成修复。\n' \
    "$stage" >&2
  if [[ "$cleanup_incomplete" == "1" ]]; then
    printf 'Automatic cleanup was incomplete. The recovery watchdog was not unloaded unless the user Agent stopped and owned power was restored. Keep the MacBook open and run the bundled uninstaller before retrying.\n' >&2
    printf '自动清理未完全成功。只有确认用户 Agent 已停止且接管的电源状态已恢复后，安装器才会卸载恢复 watchdog。请先保持开盖，运行随包卸载器，再重新安装。\n' >&2
  else
    /usr/bin/open -n "$app_target" >/dev/null 2>&1 || true
  fi
  exit 1
}

/usr/bin/pkill -x "Codex Lid Keeper" >/dev/null 2>&1 || true
if /bin/launchctl print "$user_agent_service" >/dev/null 2>&1; then
  /bin/launchctl bootout "$user_agent_service"
fi

if /usr/bin/sudo /bin/test -f "$ownership_file"; then
  ownership_restore_tool="$binary_target"
  if [[ ! -x "$ownership_restore_tool" ]]; then
    ownership_restore_tool="$binary_source"
  fi
  current_controller="$binary_source"
  if [[ -x "$app_target/Contents/Resources/codex-lid-keeper" ]]; then
    current_controller="$app_target/Contents/Resources/codex-lid-keeper"
  fi
  "$current_controller" emergency-restore || true
  /usr/bin/sudo "$ownership_restore_tool" power restore
  if /usr/bin/sudo /bin/test -f "$ownership_file"; then
    printf 'The prior power ownership record still exists after restore; refusing to replace recovery components.\n' >&2
    exit 1
  fi
fi

if /usr/bin/sudo /bin/launchctl print \
  "$recovery_service" >/dev/null 2>&1; then
  /usr/bin/sudo /bin/launchctl bootout "$recovery_service"
fi

/usr/bin/sudo /usr/bin/install -d -o root -g wheel -m 0755 \
  /Library/PrivilegedHelperTools
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0755 \
  "$binary_source" "$binary_target"
/usr/bin/sudo /usr/bin/install -d -o root -g wheel -m 0755 \
  /etc/sudoers.d
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0440 \
  "$sudoers_stage" "$sudoers_target"
/usr/bin/sudo /usr/bin/install -o root -g wheel -m 0644 \
  "$daemon_source" "$daemon_target"

app_source_parent="$(cd "$(dirname "$app_source")" && pwd -P)"
app_source_resolved="$app_source_parent/$(basename "$app_source")"
if [[ "$app_source_resolved" != "$app_target" ]]; then
  /usr/bin/sudo /bin/rm -rf "$app_stage"
  /usr/bin/sudo /usr/bin/ditto "$app_source" "$app_stage"
  /usr/bin/sudo /usr/bin/codesign --verify --deep --strict "$app_stage"
  /usr/bin/sudo /bin/rm -rf "$app_target"
  /usr/bin/sudo /bin/mv "$app_stage" "$app_target"
fi
/usr/bin/sudo /usr/sbin/chown -R "$console_user:$console_group" "$app_target"

/bin/mkdir -p "$(dirname "$agent_target")"
/usr/bin/install -m 0644 "$agent_source" "$agent_target"

if ! /usr/bin/sudo /bin/launchctl bootstrap system "$daemon_target"; then
  component_startup_failed "recovery watchdog"
fi

if ! /bin/launchctl bootstrap "gui/$console_uid" "$agent_target"; then
  component_startup_failed "user agent"
fi
if ! /bin/launchctl kickstart -k "$user_agent_service"; then
  component_startup_failed "user agent kickstart"
fi

hooks_tool="$app_target/Contents/Resources/codex-lid-keeper"
hooks_failed=0
if ! "$hooks_tool" hooks install \
  --file "$hooks_file" \
  --command "$hook_command"; then
  hooks_failed=1
elif ! "$hooks_tool" hooks verify \
  --file "$hooks_file" \
  --command "$hook_command"; then
  hooks_failed=1
fi

if [[ "$hooks_failed" == "1" ]]; then
  printf '\nHooks installation did not complete, but the system components are installed.\n' >&2
  printf 'Open Codex Lid Keeper > Settings > Permissions and choose “Install Hooks”, or run:\n' >&2
  printf '  "%s" hooks install --file "%s" --command "%s"\n' \
    "$hooks_tool" "$hooks_file" "$hook_command" >&2
  printf 'Hooks 安装未完成；系统组件已经就绪。请在 App 的“设置 > 权限”中重试，或执行上面的恢复命令。\n' >&2
  /usr/bin/open -n "$app_target" >/dev/null 2>&1 || true
  exit 1
fi

/usr/bin/open -n "$app_target"

printf '\nInstalled Codex Lid Keeper.\n'
printf 'Codex Lid Keeper 已安装完成。\n\n'
printf 'App: %s\n' "$app_target"
printf 'Next / 下一步: open /hooks in Codex and trust the five new lifecycle Hooks.\n'
printf 'Status / 状态: %s status\n' \
  "$app_target/Contents/Resources/codex-lid-keeper"
printf 'Emergency restore / 紧急恢复: %s\n' \
  "$app_target/Contents/Resources/Installer/emergency-restore.sh"
