#!/usr/bin/env python3
"""Tests for the dependency-free Karabiner generator."""

from __future__ import annotations

import importlib.util
import json
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/generate-karabiner"
SPEC = importlib.util.spec_from_loader(
    "generate_karabiner", SourceFileLoader("generate_karabiner", str(SCRIPT))
)
assert SPEC and SPEC.loader
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class GeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle_id = generator.TERMINAL_BUNDLE_ID

    def tearDown(self) -> None:
        generator.TERMINAL_BUNDLE_ID = self.bundle_id

    def test_generated_structure_matches_committed_json(self) -> None:
        committed = json.loads(generator.OUT.read_text(encoding="utf-8"))
        self.assertEqual(generator.build(), committed)

    def test_terminal_bundle_override_changes_only_launch_command(self) -> None:
        default = generator.build()
        generator.TERMINAL_BUNDLE_ID = "com.apple.Terminal"
        overridden = generator.build()
        default["profiles"][1]["complex_modifications"]["rules"][-4]["manipulators"][0]["to"][0][
            "shell_command"
        ] = "open -b com.apple.Terminal"
        self.assertEqual(overridden, default)

    def test_invalid_terminal_bundle_is_rejected(self) -> None:
        generator.TERMINAL_BUNDLE_ID = "Terminal Application"
        with self.assertRaisesRegex(ValueError, "invalid TERMINAL_BUNDLE_ID"):
            generator.build()


if __name__ == "__main__":
    unittest.main()
