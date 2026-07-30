#!/usr/bin/env python3

import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hooks_config


COMMAND = "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper hook"


class HooksConfigTests(unittest.TestCase):
    def test_install_preserves_existing_hooks(self) -> None:
        document = {
            "description": "personal hooks",
            "hooks": {
                "Stop": [
                    {
                        "hooks": [
                            {"type": "command", "command": "/tmp/existing"}
                        ]
                    }
                ]
            },
        }

        self.assertTrue(hooks_config.install_keeper_hooks(document, COMMAND))
        self.assertEqual(document["description"], "personal hooks")
        stop_commands = [
            handler["command"]
            for group in document["hooks"]["Stop"]
            for handler in group["hooks"]
        ]
        self.assertEqual(stop_commands, ["/tmp/existing", COMMAND])
        self.assertEqual(hooks_config.verify_keeper_hooks(document, COMMAND), [])
        keeper_handlers = [
            handler
            for groups in document["hooks"].values()
            for group in groups
            for handler in group["hooks"]
            if handler.get("command") == COMMAND
        ]
        self.assertTrue(keeper_handlers)
        self.assertTrue(
            all(
                handler["timeout"] == hooks_config.KEEPER_TIMEOUT_SECONDS
                for handler in keeper_handlers
            )
        )

    def test_install_is_idempotent(self) -> None:
        document: dict = {}
        hooks_config.install_keeper_hooks(document, COMMAND)
        snapshot = json.dumps(document, sort_keys=True)

        self.assertFalse(hooks_config.install_keeper_hooks(document, COMMAND))
        self.assertEqual(json.dumps(document, sort_keys=True), snapshot)

    def test_verify_rejects_stale_timeout(self) -> None:
        document: dict = {}
        hooks_config.install_keeper_hooks(document, COMMAND)
        document["hooks"]["Stop"][0]["hooks"][0]["timeout"] = 3
        self.assertEqual(
            hooks_config.verify_keeper_hooks(document, COMMAND),
            ["Stop"],
        )

    def test_verify_rejects_mixed_duplicate_handlers(self) -> None:
        document: dict = {}
        hooks_config.install_keeper_hooks(document, COMMAND)
        document["hooks"]["Stop"][0]["hooks"].append(
            {"type": "command", "command": COMMAND, "timeout": 3}
        )
        self.assertEqual(
            hooks_config.verify_keeper_hooks(document, COMMAND),
            ["Stop"],
        )
        malformed_documents = (
            {"unexpected": True},
            {"hooks": {"Stop": ["not-an-object"]}},
            {"hooks": {"Stop": [{"hooks": "not-an-array"}]}},
            {"hooks": {"Stop": [{"hooks": ["not-an-object"]}]}},
            {"hooks": {"SessionStart": [{"matcher": 42}]}},
            {
                "hooks": {
                    "PreCompact": [{"hooks": [{"type": "command"}]}]
                }
            },
            {
                "hooks": {
                    "PermissionRequest": [
                        {
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": "/tmp/unrelated",
                                    "async": "yes",
                                }
                            ]
                        }
                    ]
                }
            },
        )
        for malformed in malformed_documents:
            with self.subTest(document=malformed):
                snapshot = json.dumps(malformed, sort_keys=True)
                with self.assertRaises(hooks_config.HooksConfigError):
                    hooks_config.install_keeper_hooks(malformed, COMMAND)
                self.assertEqual(
                    json.dumps(malformed, sort_keys=True),
                    snapshot,
                )

    def test_verify_rejects_non_exact_timeout(self) -> None:
        for timeout in (1.0, 1.9, True, 1 << 64):
            with self.subTest(timeout=timeout):
                document: dict = {}
                hooks_config.install_keeper_hooks(document, COMMAND)
                document["hooks"]["Stop"][0]["hooks"][0]["timeout"] = timeout
                with self.assertRaises(hooks_config.HooksConfigError):
                    hooks_config.verify_keeper_hooks(document, COMMAND)

    def test_remove_only_removes_keeper(self) -> None:
        document = {
            "hooks": {
                "Stop": [
                    {
                        "hooks": [
                            {"type": "command", "command": "/tmp/existing"},
                            {"type": "command", "command": COMMAND},
                        ]
                    }
                ]
            }
        }

        self.assertTrue(hooks_config.remove_keeper_hooks(document, COMMAND))
        self.assertEqual(
            document["hooks"]["Stop"][0]["hooks"],
            [{"type": "command", "command": "/tmp/existing"}],
        )

    def test_empty_unrelated_group_is_preserved(self) -> None:
        empty_group = {"matcher": "preserve-empty", "hooks": []}
        matcher_only = {"matcher": "preserve-missing-hooks"}
        document = {"hooks": {"Stop": [empty_group, matcher_only]}}

        hooks_config.install_keeper_hooks(document, COMMAND)
        hooks_config.remove_keeper_hooks(document, COMMAND)

        self.assertEqual(
            document["hooks"]["Stop"],
            [empty_group, matcher_only],
        )

    def test_atomic_file_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hooks.json"
            path.write_text('{"hooks": {}}\n', encoding="utf-8")
            document = hooks_config.load_document(path)
            hooks_config.install_keeper_hooks(document, COMMAND)
            backup = hooks_config.write_document(path, document, make_backup=True)

            self.assertIsNotNone(backup)
            self.assertTrue(backup.exists())
            self.assertEqual(
                stat.S_IMODE(backup.stat().st_mode),
                0o600,
            )
            self.assertEqual(
                hooks_config.verify_keeper_hooks(
                    hooks_config.load_document(path),
                    COMMAND,
                ),
                [],
            )


if __name__ == "__main__":
    unittest.main()
