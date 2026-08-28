#!/usr/bin/env python3
"""Install, check, or remove this project's native AppKit editing bindings."""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


TARGET = Path.home() / "Library/KeyBindings/DefaultKeyBinding.dict"
STATE = (
    Path.home()
    / "Library/Application Support/karabiner-linux-mode/appkit-keybindings-state.plist"
)

# Fn+Left/Right on a compact Apple keyboard produce the Home/End function-key
# characters below. AppKit normally assigns unshifted Home/End to scrolling;
# these bindings give them Linux-style line movement instead.
BASE_MANAGED = {
    "\uf729": "moveToBeginningOfLine:",
    "\uf72b": "moveToEndOfLine:",
    "$\uf729": "moveToBeginningOfLineAndModifySelection:",
    "$\uf72b": "moveToEndOfLineAndModifySelection:",
}
MANAGED = {
    **BASE_MANAGED,
    # [1] becomes Command before AppKit sees it. Command+Home/End therefore
    # represents Linux Ctrl+Home/End on the compact keyboard.
    "@\uf729": "moveToBeginningOfDocument:",
    "@\uf72b": "moveToEndOfDocument:",
    "@$\uf729": "moveToBeginningOfDocumentAndModifySelection:",
    "@$\uf72b": "moveToEndOfDocumentAndModifySelection:",
    # [1]+Fn+Delete produces Command+Forward-Delete after the positional
    # remapping. AppKit has no useful default for that combination.
    "@\uf728": "deleteWordForward:",
}


def read_plist(path: Path) -> dict[str, Any]:
    """Read XML/binary plists and the old-style dictionaries AppKit accepts."""
    if not path.exists():
        return {}
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except plistlib.InvalidFileException:
        converted = subprocess.run(
            ["plutil", "-convert", "xml1", "-o", "-", str(path)],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout
        value = plistlib.loads(converted)
    if not isinstance(value, dict):
        raise ValueError(f"{path} does not contain a dictionary")
    return value


def write_plist(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            plistlib.dump(value, stream, fmt=plistlib.FMT_XML, sort_keys=False)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def install() -> int:
    bindings = read_plist(TARGET)

    if STATE.exists():
        state = read_plist(STATE)
        if not isinstance(state.get("previous"), dict):
            raise ValueError(f"unrecognized ownership record: {STATE}")
        if state.get("version") == 1:
            installed_before = BASE_MANAGED
        elif state.get("version") == 2 and isinstance(state.get("installed"), dict):
            installed_before = state["installed"]
        else:
            raise ValueError(f"unrecognized ownership record: {STATE}")

        # Restore keys that this project managed in an older version but no
        # longer owns. Preserve them instead if the user changed them since the
        # last install.
        for key, old_installed_value in installed_before.items():
            if key in MANAGED or bindings.get(key) != old_installed_value:
                continue
            if key in state["previous"]:
                bindings[key] = state["previous"].pop(key)
            else:
                bindings.pop(key, None)

        # Record original values for keys introduced by a newer project version
        # before replacing them. Existing ownership always traces back to the
        # first installation, not merely the most recent reinstall.
        for key in MANAGED.keys() - installed_before.keys():
            if key in bindings:
                state["previous"][key] = bindings[key]
        state["version"] = 2
        state["installed"] = MANAGED
    else:
        state = {
            "version": 2,
            "target_existed": TARGET.exists(),
            "previous": {key: bindings[key] for key in MANAGED if key in bindings},
            "installed": MANAGED,
        }

    # Save original values and ownership before changing the target, so an
    # interrupted installation remains recoverable.
    write_plist(STATE, state)

    changed = any(bindings.get(key) != value for key, value in MANAGED.items())
    bindings.update(MANAGED)
    write_plist(TARGET, bindings)

    verb = "Installed" if changed else "Confirmed"
    print(f"{verb} AppKit Linux-editing bindings -> {TARGET}")
    print("Restart open native applications (including Notes) before testing.")
    return 0


def uninstall() -> int:
    if not STATE.exists():
        print("No installer-managed AppKit key bindings were found; nothing changed.")
        return 0

    state = read_plist(STATE)
    if not isinstance(state.get("previous"), dict):
        raise ValueError(f"unrecognized ownership record: {STATE}")
    if state.get("version") == 1:
        installed = BASE_MANAGED
    elif state.get("version") == 2 and isinstance(state.get("installed"), dict):
        installed = state["installed"]
    else:
        raise ValueError(f"unrecognized ownership record: {STATE}")

    bindings = read_plist(TARGET)
    previous = state["previous"]
    preserved_changes: list[str] = []

    for key, installed_value in installed.items():
        if bindings.get(key) != installed_value:
            if key in bindings:
                preserved_changes.append(key)
            continue
        if key in previous:
            bindings[key] = previous[key]
        else:
            bindings.pop(key, None)

    if bindings or state.get("target_existed", False):
        write_plist(TARGET, bindings)
    elif TARGET.exists():
        TARGET.unlink()

    STATE.unlink()
    try:
        STATE.parent.rmdir()
    except OSError:
        pass

    print(f"Removed installer-managed AppKit Linux-editing bindings from {TARGET}")
    if preserved_changes:
        print(
            "Preserved bindings changed after installation: "
            + ", ".join(repr(key) for key in preserved_changes)
        )
    print("Restart open native applications to return to their default behavior.")
    return 0


def check() -> int:
    if not STATE.exists() or not TARGET.exists():
        print("AppKit Linux-editing bindings are not installed")
        return 1
    bindings = read_plist(TARGET)
    missing = [key for key, value in MANAGED.items() if bindings.get(key) != value]
    if missing:
        print(f"AppKit Linux-editing bindings differ at {len(missing)} managed key(s)")
        return 1
    print("AppKit Linux-editing bindings are installed")
    return 0


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"install", "uninstall", "check"}:
        print(f"usage: {Path(sys.argv[0]).name} install|uninstall|check", file=sys.stderr)
        return 2
    try:
        return {"install": install, "uninstall": uninstall, "check": check}[sys.argv[1]]()
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
