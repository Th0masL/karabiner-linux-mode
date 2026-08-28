#!/usr/bin/env python3
"""Tests for reversible ownership of the installed Karabiner profile."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("manage-karabiner-profile.py")
SPEC = importlib.util.spec_from_file_location("manage_karabiner_profile", SCRIPT)
assert SPEC and SPEC.loader
manager = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manager)


class KarabinerProfileManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.output = io.StringIO()
        self.redirect = contextlib.redirect_stdout(self.output)
        self.redirect.__enter__()
        self.addCleanup(self.redirect.__exit__, None, None, None)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        manager.REFERENCE = self.root / "karabiner.json"
        manager.LIVE = self.root / "live/karabiner.json"
        manager.STATE = self.root / "state/karabiner-profile-state.json"
        self.layout = {
            "name": "Linux",
            "selected": True,
            "simple_modifications": [
                {"from": {"key_code": "left_control"}, "to": [{"key_code": "left_command"}]}
            ],
            "complex_modifications": {"rules": [{"description": "owned", "manipulators": []}]},
        }
        manager.write_json(
            manager.REFERENCE,
            {"profiles": [{"name": "Default"}, self.layout]},
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_live(self, profiles: list[dict[str, object]]) -> None:
        manager.write_json(manager.LIVE, {"global": {"keep": True}, "profiles": profiles})

    def test_new_profile_is_removed_and_other_config_is_preserved(self) -> None:
        self.write_live([{"name": "Default", "selected": True, "custom": 1}])

        self.assertEqual(manager.install("Linux"), 0)
        self.assertEqual(manager.check("Linux"), 0)
        installed = manager.read_json(manager.LIVE)
        self.assertEqual([p["name"] for p in installed["profiles"]], ["Default", "Linux"])
        self.assertTrue(manager.STATE.exists())

        self.assertEqual(manager.uninstall(), 0)
        restored = manager.read_json(manager.LIVE)
        self.assertEqual(restored["global"], {"keep": True})
        self.assertEqual(restored["profiles"], [{"name": "Default", "selected": True, "custom": 1}])
        self.assertFalse(manager.STATE.exists())

    def test_existing_named_profile_and_active_profile_are_restored(self) -> None:
        original_linux = {"name": "Linux", "selected": False, "user": "original"}
        self.write_live(
            [
                {"name": "Default", "selected": False},
                {"name": "Work", "selected": True},
                original_linux,
            ]
        )

        self.assertEqual(manager.install("Linux"), 0)
        self.assertEqual(manager.uninstall(), 0)
        restored = manager.read_json(manager.LIVE)["profiles"]
        self.assertEqual(next(p for p in restored if p["name"] == "Linux"), original_linux)
        self.assertTrue(next(p for p in restored if p["name"] == "Work")["selected"])

    def test_legacy_matching_profile_is_adopted_then_removed(self) -> None:
        legacy = dict(self.layout)
        self.write_live([{"name": "Default", "selected": False}, legacy])

        self.assertEqual(manager.install("Linux"), 0)
        state = manager.read_json(manager.STATE)
        self.assertFalse(state["target_existed"])
        self.assertEqual(manager.uninstall(), 0)
        self.assertEqual(
            [p["name"] for p in manager.read_json(manager.LIVE)["profiles"]],
            ["Default"],
        )

    def test_reinstall_keeps_the_first_preinstallation_profile(self) -> None:
        original = {"name": "Linux", "selected": True, "user": "original"}
        self.write_live([original])

        self.assertEqual(manager.install("Linux"), 0)
        self.assertEqual(manager.install("Linux"), 0)
        self.assertEqual(manager.uninstall(), 0)
        restored = manager.read_json(manager.LIVE)["profiles"]
        self.assertEqual(next(p for p in restored if p["name"] == "Linux"), original)

    def test_uninstall_refuses_a_profile_edited_after_installation(self) -> None:
        self.write_live([{"name": "Default", "selected": True}])
        self.assertEqual(manager.install("Linux"), 0)
        live = manager.read_json(manager.LIVE)
        next(p for p in live["profiles"] if p["name"] == "Linux")["user_edit"] = True
        manager.write_json(manager.LIVE, live)

        with self.assertRaisesRegex(ValueError, "changed after installation"):
            manager.uninstall()
        self.assertEqual(manager.check(), 1)
        self.assertTrue(manager.STATE.exists())
        self.assertTrue(
            next(p for p in manager.read_json(manager.LIVE)["profiles"] if p["name"] == "Linux")["user_edit"]
        )

    def test_uninstall_refuses_when_an_owned_profile_was_removed_manually(self) -> None:
        self.write_live([{"name": "Default", "selected": True}])
        self.assertEqual(manager.install("Linux"), 0)
        live = manager.read_json(manager.LIVE)
        live["profiles"] = [p for p in live["profiles"] if p["name"] != "Linux"]
        manager.write_json(manager.LIVE, live)

        with self.assertRaisesRegex(ValueError, "missing"):
            manager.uninstall()
        self.assertEqual(manager.check(), 1)
        self.assertTrue(manager.STATE.exists())

    def test_check_requires_an_ownership_record(self) -> None:
        self.write_live([{"name": "Default", "selected": True}, self.layout])
        self.assertEqual(manager.check("Linux"), 1)


if __name__ == "__main__":
    unittest.main()
