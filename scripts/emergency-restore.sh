#!/usr/bin/env bash
set -euo pipefail

controller_binary="/Applications/Codex Lid Keeper.app/Contents/Resources/codex-lid-keeper"
root_helper="/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
ownership_file="/var/db/com.zundu.codex-lid-keeper.power.json"

if [[ -x "$root_helper" ]]; then
  if [[ -x "$controller_binary" ]]; then
    "$controller_binary" emergency-restore || true
  else
    "$root_helper" emergency-restore || true
  fi
  sudo "$root_helper" power restore
  printf 'Codex Lid Keeper ownership was restored and automation was paused.\n'
  exit 0
fi

if [[ -f "$ownership_file" ]]; then
  printf 'The ownership record exists but the helper binary is missing.\n' >&2
  printf 'Inspect the record and current pmset state before changing anything:\n' >&2
  printf '  sudo plutil -p %s\n' "$ownership_file" >&2
  printf '  pmset -g custom\n' >&2
  exit 1
fi

printf 'No installed helper or ownership record was found; nothing to restore.\n'
