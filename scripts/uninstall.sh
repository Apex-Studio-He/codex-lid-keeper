#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
binary_target="/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
app_target="/Applications/Codex Lid Keeper.app"
sudoers_target="/etc/sudoers.d/codex-lid-keeper"
daemon_target="/Library/LaunchDaemons/com.zundu.codex-lid-keeper.recovery.plist"
agent_target="${HOME:?}/Library/LaunchAgents/com.zundu.codex-lid-keeper.agent.plist"
hooks_file="${HOME:?}/.codex/hooks.json"
hook_command="$binary_target hook"
console_uid="$(id -u)"

/usr/bin/pkill -x "Codex Lid Keeper" >/dev/null 2>&1 || true

if [[ -x "$binary_target" ]]; then
  "$binary_target" emergency-restore || true
  sudo "$binary_target" power restore
fi

/bin/launchctl bootout \
  "gui/$console_uid/com.zundu.codex-lid-keeper.agent" >/dev/null 2>&1 || true
rm -f "$agent_target"

/usr/bin/python3 "$script_dir/hooks_config.py" remove \
  --file "$hooks_file" \
  --command "$hook_command"

sudo /bin/launchctl bootout \
  system/com.zundu.codex-lid-keeper.recovery >/dev/null 2>&1 || true
sudo rm -f "$daemon_target"
sudo rm -f "$sudoers_target"
sudo rm -f "$binary_target"
sudo /bin/rm -rf "$app_target"

printf 'Codex Lid Keeper was uninstalled and its owned power state was restored.\n'
printf 'User logs/config were preserved at: %s\n' \
  "${HOME:?}/Library/Application Support/CodexLidKeeper"
