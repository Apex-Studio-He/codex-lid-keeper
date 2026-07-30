#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
binary="${1:-$project_dir/.build/release/codex-lid-keeper}"
installer="$script_dir/install_components.sh"
uninstaller="$script_dir/uninstall_components.sh"
preflight="$script_dir/preflight_hooks.sh"

fail() {
  printf 'installer safety test failed: %s\n' "$1" >&2
  exit 1
}

line_of() {
  local pattern="$1"
  local file="$2"
  /usr/bin/grep -n -m 1 -E "$pattern" "$file" \
    | /usr/bin/cut -d: -f1
}

assert_before() {
  local earlier_pattern="$1"
  local later_pattern="$2"
  local file="$3"
  local description="$4"
  local earlier_line
  local later_line

  earlier_line="$(line_of "$earlier_pattern" "$file")" \
    || fail "missing invariant: $description"
  later_line="$(line_of "$later_pattern" "$file")" \
    || fail "missing comparison point: $description"
  if ((earlier_line >= later_line)); then
    fail "$description"
  fi
}

if [[ ! -x "$binary" ]]; then
  fail "build the release CLI before running this test ($binary)"
fi

assert_before \
  'console_uid.*==.*"0"' \
  '/usr/bin/pkill' \
  "$uninstaller" \
  "the uninstaller must reject root before changing user or system state"

assert_before \
  'gui/.+com\.zundu\.codex-lid-keeper\.agent' \
  'power restore' \
  "$uninstaller" \
  "the user agent must be stopped before the root power restore"

/usr/bin/grep -q 'ownership_file=' "$uninstaller" \
  || fail "the uninstaller must check the root ownership record"
/usr/bin/grep -q 'Could not remove the login item' "$uninstaller" \
  || fail "the uninstaller must surface login-item cleanup failures"
/usr/bin/grep -q 'restore_tool="\$controller_binary"' "$uninstaller" \
  || fail "the installed app CLI must be a fallback restore tool"
/usr/bin/grep -q 'restore_tool="\$bundled_binary"' "$uninstaller" \
  || fail "the package CLI must be a fallback restore tool"
/usr/bin/grep -q '\.build/release/codex-lid-keeper' "$uninstaller" \
  || fail "the source uninstaller must find the Release CLI"
/usr/bin/grep -q 'ownership_restore_tool="\$binary_source"' "$installer" \
  || fail "an upgrade package must recover owned power if the old Helper is missing"
/usr/bin/grep -q 'component_startup_failed "recovery watchdog"' "$installer" \
  || fail "recovery bootstrap failure needs a safe repair path"
/usr/bin/grep -q 'component_startup_failed "user agent"' "$installer" \
  || fail "user-agent bootstrap failure needs a safe repair path"
/usr/bin/grep -q 'No Hooks were added' "$installer" \
  || fail "startup failure must explain the retained safe state"
/usr/bin/grep -q 'user_agent_stopped.*==.*"1"' "$installer" \
  || fail "startup cleanup must gate watchdog removal on stopping the user agent"
/usr/bin/grep -q 'ownership_cleared.*==.*"1"' "$installer" \
  || fail "startup cleanup must gate watchdog removal on restoring owned power"
/usr/bin/grep -q 'recovery watchdog was not unloaded unless' "$installer" \
  || fail "incomplete cleanup must explain the retained safety boundary"
assert_before \
  'bootstrap system' \
  'bootstrap "gui/' \
  "$installer" \
  "the root recovery watchdog must load before the user agent"

temporary_dir="$(mktemp -d /tmp/codex-lid-keeper-installer-test.XXXXXX)"
cleanup() {
  /bin/rm -rf "$temporary_dir"
}
trap cleanup EXIT

fake_bin="$temporary_dir/bin"
/bin/mkdir -p "$fake_bin" "$temporary_dir/home"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'case "${1:-}" in'
  printf '%s\n' '  -u) printf "0\n" ;;'
  printf '%s\n' '  -un) printf "root\n" ;;'
  printf '%s\n' '  -gn) printf "wheel\n" ;;'
  printf '%s\n' '  *) exit 2 ;;'
  printf '%s\n' 'esac'
} > "$fake_bin/id"
/bin/chmod 0755 "$fake_bin/id"

root_output="$temporary_dir/root-uninstall.txt"
if HOME="$temporary_dir/home" \
  PATH="$fake_bin:/usr/bin:/bin" \
  "$uninstaller" >"$root_output" 2>&1; then
  fail "the uninstaller accepted a root invocation"
fi
/usr/bin/grep -q 'not as root' "$root_output" \
  || fail "the root refusal did not explain how to run the uninstaller"

valid_hooks="$temporary_dir/valid-hooks.json"
invalid_hooks="$temporary_dir/invalid-hooks.json"
missing_hooks="$temporary_dir/missing-hooks.json"
printf '%s\n' \
  '{"description":"personal hooks","hooks":{}}' > "$valid_hooks"
printf '%s\n' \
  '{"hooks":[]}' > "$invalid_hooks"

valid_before="$(/usr/bin/shasum -a 256 "$valid_hooks")"
"$preflight" "$binary" "$valid_hooks" \
  "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook"
valid_after="$(/usr/bin/shasum -a 256 "$valid_hooks")"
if [[ "$valid_before" != "$valid_after" ]]; then
  fail "Hooks preflight modified a valid user configuration"
fi

invalid_before="$(/usr/bin/shasum -a 256 "$invalid_hooks")"
if "$preflight" "$binary" "$invalid_hooks" \
  "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook" \
  >/dev/null 2>&1; then
  fail "Hooks preflight accepted an invalid top-level hooks value"
fi
invalid_after="$(/usr/bin/shasum -a 256 "$invalid_hooks")"
if [[ "$invalid_before" != "$invalid_after" ]]; then
  fail "Hooks preflight modified an invalid user configuration"
fi

"$preflight" "$binary" "$missing_hooks" \
  "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook"
if [[ -e "$missing_hooks" ]]; then
  fail "Hooks preflight created the user's previously missing hooks file"
fi

assert_before \
  '^"\$preflight_script"' \
  '/usr/bin/sudo -v' \
  "$installer" \
  "Hooks validation must finish before administrator authentication"

/usr/bin/grep -q 'Hooks installation did not complete' "$installer" \
  || fail "a post-install Hooks failure needs an explicit recovery path"

printf 'Installer safety checks passed.\n'
