#!/usr/bin/env python3
"""Exercise the built CLI lifecycle using only an isolated dry-run home."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def run(
    binary: Path,
    environment: dict[str, str],
    *arguments: str,
    stdin: dict | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(binary), *arguments],
        input=json.dumps(stdin) if stdin is not None else None,
        text=True,
        capture_output=True,
        check=True,
        env=environment,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--binary",
        type=Path,
        default=Path(".build/debug/codex-lid-keeper"),
    )
    args = parser.parse_args()
    binary = args.binary.resolve()

    with tempfile.TemporaryDirectory(prefix="codex-lid-keeper-e2e.") as directory:
        test_home = Path(directory)
        environment = dict(os.environ)
        environment["CODEX_LID_KEEPER_HOME"] = str(test_home)
        environment["CODEX_LID_KEEPER_DRY_RUN"] = "1"
        environment["CODEX_LID_KEEPER_TEST_POWER"] = "ac"

        # Create the default config. Power-source injection is accepted only
        # while dry-run mode is active, so this test cannot alter live policy.
        run(binary, environment, "status", "--json")
        config_file = (
            test_home
            / "Library"
            / "Application Support"
            / "CodexLidKeeper"
            / "config.json"
        )
        state_file = config_file.with_name("state.json")

        daemon = subprocess.Popen(
            [str(binary), "daemon"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        try:
            deadline = time.monotonic() + 2
            while not state_file.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            assert state_file.exists(), "daemon did not complete startup recovery"
            time.sleep(0.2)
            idle_state_mtime = state_file.stat().st_mtime_ns
            time.sleep(2.2)
            assert state_file.stat().st_mtime_ns == idle_state_mtime, (
                "idle daemon rewrote state without an event or owned power"
            )
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=2)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=2)

        hook_started_at = time.perf_counter()
        started = run(
            binary,
            environment,
            "hook",
            stdin={
                "session_id": "s1",
                "turn_id": "t1",
                "cwd": "/tmp/demo-project",
                "hook_event_name": "UserPromptSubmit",
                "prompt": "not persisted",
            },
        )
        hook_elapsed = time.perf_counter() - hook_started_at
        assert json.loads(started.stdout) == {}
        assert hook_elapsed < 1.0, f"Hook took {hook_elapsed:.3f}s"

        queued = json.loads(
            run(binary, environment, "status", "--json").stdout
        )
        assert queued["activeLeases"] == []
        assert queued["pendingEventCount"] == 1
        assert queued["powerOwned"] is False

        event_directory = config_file.parent / "events" / "pending"
        event_files = list(event_directory.glob("*.json"))
        assert len(event_files) == 1
        queued_event = event_files[0].read_text(encoding="utf-8")
        assert "not persisted" not in queued_event
        assert "/tmp/demo-project" not in queued_event

        run(binary, environment, "daemon", "--once")
        active = json.loads(run(binary, environment, "status", "--json").stdout)
        assert len(active["activeLeases"]) == 1
        assert active["activeLeases"][0]["projectName"] == "demo-project"
        assert active["pendingEventCount"] == 0
        assert active["powerOwned"] is True

        assert "not persisted" not in state_file.read_text(encoding="utf-8")

        ended = run(
            binary,
            environment,
            "hook",
            stdin={
                "session_id": "s1",
                "cwd": "/tmp/demo-project",
                "hook_event_name": "SessionEnd",
                "reason": "other",
            },
        )
        assert json.loads(ended.stdout) == {}
        awaiting_release = json.loads(
            run(binary, environment, "status", "--json").stdout
        )
        assert len(awaiting_release["activeLeases"]) == 1
        assert awaiting_release["pendingEventCount"] == 1

        run(binary, environment, "daemon", "--once")
        inactive = json.loads(
            run(binary, environment, "status", "--json").stdout
        )
        assert inactive["activeLeases"] == []
        assert inactive["powerOwned"] is False

        # Emergency restore must not depend on a readable configuration file.
        run(
            binary,
            environment,
            "hook",
            stdin={
                "session_id": "s2",
                "turn_id": "t2",
                "cwd": "/tmp/another-project",
                "hook_event_name": "UserPromptSubmit",
                "prompt": "also not persisted",
            },
        )
        run(binary, environment, "daemon", "--once")
        dry_run_marker = config_file.with_name("dry-run-power-owned")
        assert dry_run_marker.exists()
        config_file.write_text("{malformed", encoding="utf-8")
        restored = run(binary, environment, "emergency-restore")
        assert "restored" in restored.stdout
        recovered_state = json.loads(state_file.read_text(encoding="utf-8"))
        assert recovered_state["automationEnabled"] is False
        assert recovered_state["leases"] == {}
        assert not dry_run_marker.exists()

    print("non-blocking dry-run Hook lifecycle passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
