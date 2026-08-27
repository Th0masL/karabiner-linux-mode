#!/usr/bin/env python3
"""Tests for the reversible VS Code/VSCodium keybinding manager."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("manage-editor-keybindings.py")
SPEC = importlib.util.spec_from_file_location("manage_editor_keybindings", SCRIPT)
assert SPEC and SPEC.loader
manager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manager)


class EditorKeybindingManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.output = io.StringIO()
        self.error_output = io.StringIO()
        self.stdout_redirect = contextlib.redirect_stdout(self.output)
        self.stderr_redirect = contextlib.redirect_stderr(self.error_output)
        self.stdout_redirect.__enter__()
        self.stderr_redirect.__enter__()
        self.addCleanup(self.stderr_redirect.__exit__, None, None, None)
        self.addCleanup(self.stdout_redirect.__exit__, None, None, None)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.reference = self.root / "reference.json"
        self.state = self.root / "state.plist"
        self.code = self.root / "Code/User/keybindings.json"
        self.codium = self.root / "VSCodium/User/keybindings.json"
        manager.REFERENCE = self.reference
        manager.STATE = self.state
        manager.EDITORS = {"VS Code": self.code, "VSCodium": self.codium}
        self.write_reference([self.binding("cmd+c", "\u0003")])

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def binding(key: str, text: str) -> dict[str, object]:
        return {
            "key": key,
            "command": "workbench.action.terminal.sendSequence",
            "args": {"text": text},
            "when": "terminalFocus",
        }

    def write_reference(self, bindings: list[dict[str, object]]) -> None:
        import json

        self.reference.write_text(json.dumps(bindings, indent=2) + "\n", encoding="utf-8")

    def test_existing_jsonc_is_restored_byte_for_byte(self) -> None:
        original = """// user header
[
  { "key": "cmd+x", "command": "example", "when": "editorTextFocus" }, // keep
]
"""
        self.code.parent.mkdir(parents=True)
        self.code.write_text(original, encoding="utf-8")

        self.assertEqual(manager.install(), 0)
        installed = self.code.read_text(encoding="utf-8")
        self.assertIn(manager.BEGIN_MARKER, installed)
        self.assertEqual(len(manager.parse_bindings(installed, self.code)), 2)

        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(self.code.read_text(encoding="utf-8"), original)

    def test_new_file_is_removed_on_uninstall(self) -> None:
        self.code.parent.mkdir(parents=True)
        self.assertEqual(manager.install(), 0)
        self.assertTrue(self.code.exists())
        self.assertEqual(manager.uninstall(), 0)
        self.assertFalse(self.code.exists())

    def test_exact_old_reference_copy_is_migrated_without_duplicates(self) -> None:
        self.code.parent.mkdir(parents=True)
        copied = self.reference.read_text(encoding="utf-8")
        self.code.write_text(copied, encoding="utf-8")

        self.assertEqual(manager.install(), 0)
        installed = manager.parse_bindings(self.code.read_text(encoding="utf-8"), self.code)
        self.assertEqual(installed, manager.parse_bindings(copied, self.reference))
        self.assertIn(manager.BEGIN_MARKER, self.code.read_text(encoding="utf-8"))

        self.assertEqual(manager.uninstall(), 0)
        self.assertFalse(self.code.exists())

    def test_reinstall_upgrades_the_owned_block(self) -> None:
        original = "[\n  {\"key\": \"cmd+x\", \"command\": \"example\"}\n]\n"
        self.code.parent.mkdir(parents=True)
        self.code.write_text(original, encoding="utf-8")
        self.assertEqual(manager.install(), 0)

        self.write_reference(
            [self.binding("cmd+c", "\u0003"), self.binding("cmd+d", "\u0004")]
        )
        self.assertEqual(manager.install(), 0)
        installed = manager.parse_bindings(self.code.read_text(encoding="utf-8"), self.code)
        self.assertEqual(len(installed), 3)
        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(self.code.read_text(encoding="utf-8"), original)

    def test_reinstall_is_idempotent(self) -> None:
        self.code.parent.mkdir(parents=True)
        self.code.write_text(manager.EMPTY_DOCUMENT, encoding="utf-8")
        self.assertEqual(manager.install(), 0)
        installed = self.code.read_bytes()
        state = self.state.read_bytes()
        backups = sorted(self.code.parent.glob("keybindings.json.backup.*"))

        self.assertEqual(manager.install(), 0)
        self.assertEqual(self.code.read_bytes(), installed)
        self.assertEqual(self.state.read_bytes(), state)
        self.assertEqual(sorted(self.code.parent.glob("keybindings.json.backup.*")), backups)

    def test_uninstall_preserves_an_edited_managed_block(self) -> None:
        self.code.parent.mkdir(parents=True)
        self.code.write_text(manager.EMPTY_DOCUMENT, encoding="utf-8")
        self.assertEqual(manager.install(), 0)
        edited = self.code.read_text(encoding="utf-8").replace(
            "workbench.action.terminal.sendSequence", "user.changed.command", 1
        )
        self.code.write_text(edited, encoding="utf-8")

        self.assertEqual(manager.uninstall(), 1)
        self.assertEqual(self.code.read_text(encoding="utf-8"), edited)
        self.assertTrue(self.state.exists())

    def test_jsonc_parser_preserves_comment_like_string_content(self) -> None:
        text = """[
  {"key":"cmd+x", "command":"send", "args":{"text":"https://x/*y*/"}},
] // trailing comment
"""
        parsed = manager.parse_bindings(text, "memory")
        self.assertEqual(parsed[0]["args"]["text"], "https://x/*y*/")


if __name__ == "__main__":
    unittest.main()
