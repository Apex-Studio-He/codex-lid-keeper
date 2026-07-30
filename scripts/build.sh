#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"

cd "$project_dir"
swift build -c release -Xswiftc -warnings-as-errors
swift run -c release --skip-build codex-lid-keeper-self-test
"$script_dir/test_installer_safety.sh" \
  "$project_dir/.build/release/codex-lid-keeper"

printf 'Built: %s\n' "$project_dir/.build/release/codex-lid-keeper"
