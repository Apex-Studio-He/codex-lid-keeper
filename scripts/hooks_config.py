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
SUPPORTED_EVENTS = (
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "SubagentStart",
    "SubagentStop",
    "Stop",
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
    validate_document(document)
    return document


def validate_document(document: dict[str, Any]) -> None:
    unsupported = set(document) - {"description", "hooks"}
    if unsupported:
        field = sorted(unsupported)[0]
        raise HooksConfigError(f"unsupported top-level field: {field}")
    description = document.get("description")
    if description is not None and not isinstance(description, str):
        raise HooksConfigError("top-level 'description' must be a string")
    if "hooks" in document and not isinstance(document["hooks"], dict):
        raise HooksConfigError("top-level 'hooks' must be an object")
    validate_known_events(document)


def is_keeper_handler(value: Any, command: str) -> bool:
    return (
        isinstance(value, dict)
        and value.get("type") == "command"
        and value.get("command") == command
    )


def is_expected_keeper_handler(value: Any, command: str) -> bool:
    timeout = value.get("timeout") if isinstance(value, dict) else None
    return (
        is_keeper_handler(value, command)
        and not isinstance(timeout, bool)
        and isinstance(timeout, int)
        and timeout == KEEPER_TIMEOUT_SECONDS
    )


def validate_known_events(document: dict[str, Any]) -> None:
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event in SUPPORTED_EVENTS:
        if event not in hooks:
            continue
        groups = hooks[event]
        if not isinstance(groups, list):
            raise HooksConfigError(f"hooks.{event} must be an array")
        for group_index, group in enumerate(groups):
            if not isinstance(group, dict):
                raise HooksConfigError(
                    f"hooks.{event}[{group_index}] must be an object"
                )
            matcher = group.get("matcher")
            if matcher is not None and not isinstance(matcher, str):
                raise HooksConfigError(
                    f"hooks.{event}[{group_index}].matcher must be a string"
                )
            handlers = group.get("hooks", [])
            if not isinstance(handlers, list):
                raise HooksConfigError(
                    f"hooks.{event}[{group_index}].hooks must be an array"
                )
            for handler_index, handler in enumerate(handlers):
                if not isinstance(handler, dict):
                    raise HooksConfigError(
                        f"hooks.{event}[{group_index}].hooks"
                        f"[{handler_index}] must be an object"
                    )
                validate_handler(
                    handler,
                    f"hooks.{event}[{group_index}].hooks[{handler_index}]",
                )


def validate_handler(handler: dict[str, Any], path: str) -> None:
    handler_type = handler.get("type")
    if handler_type not in {"command", "prompt", "agent"}:
        raise HooksConfigError(
            f"{path}.type must be 'command', 'prompt', or 'agent'"
        )
    if handler_type != "command":
        return
    if not isinstance(handler.get("command"), str):
        raise HooksConfigError(f"{path}.command must be a string")
    if "commandWindows" in handler and "command_windows" in handler:
        raise HooksConfigError(
            f"{path} cannot contain both commandWindows and command_windows"
        )
    for field in ("commandWindows", "command_windows", "statusMessage"):
        value = handler.get(field)
        if value is not None and not isinstance(value, str):
            raise HooksConfigError(f"{path}.{field} must be a string")
    for field in ("timeout", "additionalContextLimit"):
        value = handler.get(field)
        if value is not None and (
            type(value) is not int
            or value < 0
            or value > (1 << 64) - 1
        ):
            raise HooksConfigError(
                f"{path}.{field} must be an unsigned integer"
            )
    if "async" in handler and not isinstance(handler["async"], bool):
        raise HooksConfigError(f"{path}.async must be a boolean")


def remove_keeper_hooks(document: dict[str, Any], command: str) -> bool:
    validate_document(document)
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
            removed = len(filtered) != len(handlers)
            if removed:
                changed = True
            if not removed:
                kept_groups.append(group)
            elif filtered:
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
    validate_document(document)
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
    validate_document(document)
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        return list(EVENTS)
    missing: list[str] = []
    for event in EVENTS:
        keeper_handlers: list[Any] = []
        groups = hooks.get(event, [])
        if isinstance(groups, list):
            for group in groups:
                if not isinstance(group, dict):
                    continue
                handlers = group.get("hooks", [])
                if isinstance(handlers, list):
                    keeper_handlers.extend(
                        handler for handler in handlers
                        if is_keeper_handler(handler, command)
                    )
        if (
            len(keeper_handlers) != 1
            or not is_expected_keeper_handler(keeper_handlers[0], command)
        ):
            missing.append(event)
    return missing


def write_document(path: Path, document: dict[str, Any], make_backup: bool) -> Path | None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup: Path | None = None
    if make_backup and path.exists():
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = path.with_name(f"{path.name}.backup.{stamp}")
        shutil.copy2(path, backup)
        backup.chmod(0o600)

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
