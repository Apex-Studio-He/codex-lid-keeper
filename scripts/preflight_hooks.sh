#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  printf 'Usage: %s CLI HOOKS_FILE HOOK_COMMAND\n' "$0" >&2
  exit 64
fi

binary="$1"
hooks_file="$2"
hook_command="$3"

if [[ ! -x "$binary" ]]; then
  printf 'Hooks preflight CLI is missing or not executable: %s\n' \
    "$binary" >&2
  exit 1
fi

temporary_dir="$(mktemp -d /tmp/codex-lid-keeper-hooks-preflight.XXXXXX)"
candidate="$temporary_dir/hooks.json"
cleanup() {
  /bin/rm -rf "$temporary_dir"
}
trap cleanup EXIT

if [[ -e "$hooks_file" ]]; then
  if [[ ! -f "$hooks_file" || ! -r "$hooks_file" ]]; then
    printf 'Codex Hooks configuration is not a readable file: %s\n' \
      "$hooks_file" >&2
    exit 1
  fi
  /bin/cp -p "$hooks_file" "$candidate"
fi

"$binary" hooks install \
  --file "$candidate" \
  --command "$hook_command" \
  >/dev/null
"$binary" hooks verify \
  --file "$candidate" \
  --command "$hook_command" \
  >/dev/null

printf 'Codex Hooks configuration passed the non-destructive preflight.\n'
