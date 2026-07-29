#!/usr/bin/env python3
"""Merge Codex Lid Keeper lifecycle hooks without replacing unrelated hooks."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Any

EVENTS = (
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "Stop",
    "SessionEnd",
)
KEEPER_TIMEOUT_SECONDS = 1


class HooksConfigError(Exception):
    pass


def load_document(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise HooksConfigError(f"{path} is not valid UTF-8 JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise HooksConfigError(f"{path} must contain a JSON object")
    hooks = document.get("hooks")
    if hooks is not None and not isinstance(hooks, dict):
        raise HooksConfigError(f"{path}: top-level 'hooks' must be an object")
    return document


def is_keeper_handler(value: Any, command: str) -> bool:
    return (
        isinstance(value, dict)
        and value.get("type") == "command"
        and value.get("command") == command
    )


def is_expected_keeper_handler(value: Any, command: str) -> bool:
    return (
        is_keeper_handler(value, command)
        and value.get("timeout") == KEEPER_TIMEOUT_SECONDS
    )


def remove_keeper_hooks(document: dict[str, Any], command: str) -> bool:
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        return False

    changed = False
    for event in EVENTS:
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue
        kept_groups: list[Any] = []
        for group in groups:
            if not isinstance(group, dict):
                kept_groups.append(group)
                continue
            handlers = group.get("hooks")
            if not isinstance(handlers, list):
                kept_groups.append(group)
                continue
            filtered = [
                handler
                for handler in handlers
                if not is_keeper_handler(handler, command)
            ]
            if len(filtered) != len(handlers):
                changed = True
            if filtered:
                updated = dict(group)
                updated["hooks"] = filtered
                kept_groups.append(updated)
        if kept_groups:
            hooks[event] = kept_groups
        elif event in hooks:
            del hooks[event]
            changed = True
    return changed


def install_keeper_hooks(document: dict[str, Any], command: str) -> bool:
    before = json.dumps(document, sort_keys=True, separators=(",", ":"))
    remove_keeper_hooks(document, command)
    hooks = document.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise HooksConfigError("top-level 'hooks' must be an object")

    for event in EVENTS:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise HooksConfigError(f"hooks.{event} must be an array")
        groups.append(
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": command,
                        "timeout": KEEPER_TIMEOUT_SECONDS,
                    }
                ]
            }
        )
    after = json.dumps(document, sort_keys=True, separators=(",", ":"))
    return before != after


def verify_keeper_hooks(document: dict[str, Any], command: str) -> list[str]:
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        return list(EVENTS)
    missing: list[str] = []
    for event in EVENTS:
        count = 0
        groups = hooks.get(event, [])
        if isinstance(groups, list):
            for group in groups:
                if not isinstance(group, dict):
                    continue
                handlers = group.get("hooks", [])
                if isinstance(handlers, list):
                    count += sum(
                        1 for handler in handlers
                        if is_expected_keeper_handler(handler, command)
                    )
        if count != 1:
            missing.append(event)
    return missing


def write_document(path: Path, document: dict[str, Any], make_backup: bool) -> Path | None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup: Path | None = None
    if make_backup and path.exists():
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = path.with_name(f"{path.name}.backup.{stamp}")
        shutil.copy2(path, backup)

    payload = json.dumps(document, indent=2, ensure_ascii=False) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
    return backup


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "remove", "verify"))
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--command", required=True)
    args = parser.parse_args()

    try:
        document = load_document(args.file)
        if args.action == "verify":
            missing = verify_keeper_hooks(document, args.command)
            if missing:
                print("missing or duplicated events: " + ", ".join(missing))
                return 1
            print("Codex Lid Keeper hooks are configured exactly once.")
            return 0

        if args.action == "install":
            changed = install_keeper_hooks(document, args.command)
        else:
            changed = remove_keeper_hooks(document, args.command)

        if not changed:
            print("Hooks already in requested state.")
            return 0
        backup = write_document(args.file, document, make_backup=True)
        print(f"Updated {args.file}")
        if backup:
            print(f"Backup: {backup}")
        return 0
    except HooksConfigError as exc:
        print(f"hooks_config.py: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
