#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Codex Lid Keeper currently supports macOS only.\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
binary_source="$project_dir/.build/release/codex-lid-keeper"
binary_target="/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
app_source="$project_dir/dist/Codex Lid Keeper.app"
app_target="/Applications/Codex Lid Keeper.app"
sudoers_target="/etc/sudoers.d/codex-lid-keeper"
daemon_target="/Library/LaunchDaemons/com.zundu.codex-lid-keeper.recovery.plist"
agent_target="${HOME:?}/Library/LaunchAgents/com.zundu.codex-lid-keeper.agent.plist"
hooks_file="${HOME:?}/.codex/hooks.json"
hook_command="$binary_target hook"
console_user="$(id -un)"
console_group="$(id -gn)"
console_uid="$(id -u)"

if [[ "$console_uid" == "0" ]] \
  || [[ ! "$console_user" =~ ^[A-Za-z0-9_.-]+$ ]] \
  || [[ ! "$console_group" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  printf 'Run this installer from the macOS user account that runs Codex, not as root.\n' >&2
  exit 1
fi

printf 'Building and running non-privileged self-tests...\n'
"$script_dir/build.sh"
"$script_dir/build_app.sh"

stage_dir="$(mktemp -d /tmp/codex-lid-keeper-install.XXXXXX)"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

sudoers_stage="$stage_dir/codex-lid-keeper.sudoers"
printf '%s ALL=(root) NOPASSWD: %s power enable-ac, %s power enable-battery, %s power restore\n' \
  "$console_user" "$binary_target" "$binary_target" "$binary_target" \
  > "$sudoers_stage"
chmod 0440 "$sudoers_stage"

printf 'Administrator access is required to install the root-owned helper boundary.\n'
if ! sudo /usr/bin/grep -Eq \
  '^[[:space:]]*([#@]includedir)[[:space:]]+/(private/)?etc/sudoers\.d' \
  /etc/sudoers; then
  printf '/etc/sudoers does not include /etc/sudoers.d; refusing a partial install.\n' >&2
  exit 1
fi
sudo /usr/sbin/visudo -cf "$sudoers_stage" >/dev/null

sudo /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
sudo /usr/bin/install -o root -g wheel -m 0755 "$binary_source" "$binary_target"
sudo /usr/bin/install -d -o root -g wheel -m 0755 /etc/sudoers.d
sudo /usr/bin/install -o root -g wheel -m 0440 "$sudoers_stage" "$sudoers_target"
sudo /usr/bin/install -o root -g wheel -m 0644 \
  "$project_dir/Resources/com.zundu.codex-lid-keeper.recovery.plist" \
  "$daemon_target"
sudo /bin/rm -rf "$app_target"
sudo /usr/bin/ditto "$app_source" "$app_target"
sudo /usr/sbin/chown -R "$console_user:$console_group" "$app_target"

mkdir -p "$(dirname "$agent_target")"
/usr/bin/install -m 0644 \
  "$project_dir/Resources/com.zundu.codex-lid-keeper.agent.plist" \
  "$agent_target"

sudo /bin/launchctl bootout \
  system/com.zundu.codex-lid-keeper.recovery >/dev/null 2>&1 || true
sudo /bin/launchctl bootstrap system "$daemon_target"

/bin/launchctl bootout \
  "gui/$console_uid/com.zundu.codex-lid-keeper.agent" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$console_uid" "$agent_target"
/bin/launchctl kickstart -k \
  "gui/$console_uid/com.zundu.codex-lid-keeper.agent"

/usr/bin/python3 "$script_dir/hooks_config.py" install \
  --file "$hooks_file" \
  --command "$hook_command"
/usr/bin/python3 "$script_dir/hooks_config.py" verify \
  --file "$hooks_file" \
  --command "$hook_command"

/usr/bin/pkill -x "Codex Lid Keeper" >/dev/null 2>&1 || true
/usr/bin/open -n "$app_target"

printf '\nInstalled Codex Lid Keeper.\n'
printf 'App: %s\n' "$app_target"
printf 'Next: open /hooks in Codex, review the five new lifecycle hooks, and trust them if prompted.\n'
printf 'Status: %s status\n' \
  "$app_target/Contents/Resources/codex-lid-keeper"
printf 'Emergency restore: %s\n' "$project_dir/scripts/emergency-restore.sh"
