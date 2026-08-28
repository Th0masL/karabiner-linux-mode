#!/usr/bin/env python3
"""Tests for the reversible AppKit keybinding manager."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/manage-appkit-keybindings"
SPEC = importlib.util.spec_from_loader(
    "manage_appkit_keybindings",
    SourceFileLoader("manage_appkit_keybindings", str(SCRIPT)),
)
assert SPEC and SPEC.loader
manager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manager)


class AppKitKeybindingManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.output = io.StringIO()
        self.stdout_redirect = contextlib.redirect_stdout(self.output)
        self.stdout_redirect.__enter__()
        self.addCleanup(self.stdout_redirect.__exit__, None, None, None)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        manager.TARGET = self.root / "Library/KeyBindings/DefaultKeyBinding.dict"
        manager.STATE = (
            self.root
            / "Library/Application Support/karabiner-linux-mode/appkit-keybindings-state.plist"
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_target(self, bindings: dict[str, str]) -> None:
        manager.write_plist(manager.TARGET, bindings)

    def read_target(self) -> dict[str, str]:
        return manager.read_plist(manager.TARGET)

    def test_existing_bindings_are_restored_on_uninstall(self) -> None:
        overridden_key = next(iter(manager.MANAGED))
        original = {
            "^x": "userAction:",
            overridden_key: "userOriginalAction:",
        }
        self.write_target(original)

        self.assertEqual(manager.install(), 0)
        installed = self.read_target()
        self.assertEqual(installed["^x"], "userAction:")
        for key, value in manager.MANAGED.items():
            self.assertEqual(installed[key], value)
        self.assertEqual(manager.check(), 0)

        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(self.read_target(), original)
        self.assertFalse(manager.STATE.exists())

    def test_new_target_is_removed_on_uninstall(self) -> None:
        self.assertFalse(manager.TARGET.exists())
        self.assertEqual(manager.install(), 0)
        self.assertTrue(manager.TARGET.exists())
        self.assertEqual(manager.uninstall(), 0)
        self.assertFalse(manager.TARGET.exists())

    def test_reinstall_is_idempotent(self) -> None:
        self.assertEqual(manager.install(), 0)
        installed = manager.TARGET.read_bytes()
        state = manager.STATE.read_bytes()

        self.assertEqual(manager.install(), 0)
        self.assertEqual(manager.TARGET.read_bytes(), installed)
        self.assertEqual(manager.STATE.read_bytes(), state)
        self.assertIn("Confirmed", self.output.getvalue())

    def test_uninstall_preserves_a_managed_binding_changed_by_the_user(self) -> None:
        changed_key = next(iter(manager.MANAGED))
        self.assertEqual(manager.install(), 0)
        bindings = self.read_target()
        bindings[changed_key] = "userChangedAction:"
        self.write_target(bindings)

        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(self.read_target(), {changed_key: "userChangedAction:"})
        self.assertIn("Preserved bindings changed", self.output.getvalue())

    def test_version_one_state_upgrades_without_losing_original_values(self) -> None:
        old_original_key = next(iter(manager.BASE_MANAGED))
        new_key = next(iter(manager.MANAGED.keys() - manager.BASE_MANAGED.keys()))
        original = {
            "^x": "unrelatedAction:",
            old_original_key: "oldOriginalAction:",
            new_key: "newOriginalAction:",
        }
        installed_v1 = dict(original)
        installed_v1.update(manager.BASE_MANAGED)
        self.write_target(installed_v1)
        manager.write_plist(
            manager.STATE,
            {
                "version": 1,
                "target_existed": True,
                "previous": {old_original_key: original[old_original_key]},
            },
        )

        self.assertEqual(manager.install(), 0)
        state = manager.read_plist(manager.STATE)
        self.assertEqual(state["version"], 2)
        self.assertEqual(state["previous"][new_key], original[new_key])

        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(self.read_target(), original)

    def test_check_detects_a_changed_managed_binding(self) -> None:
        self.assertEqual(manager.check(), 1)
        self.assertEqual(manager.install(), 0)
        bindings = self.read_target()
        bindings[next(iter(manager.MANAGED))] = "changedAction:"
        self.write_target(bindings)
        self.assertEqual(manager.check(), 1)

    def test_write_preserves_existing_file_mode(self) -> None:
        self.write_target({"^x": "userAction:"})
        os.chmod(manager.TARGET, 0o640)
        self.assertEqual(manager.install(), 0)
        self.assertEqual(manager.TARGET.stat().st_mode & 0o777, 0o640)


if __name__ == "__main__":
    unittest.main()
