#!/usr/bin/env python3
"""Install or remove the owned Karabiner profile without touching other profiles."""

from __future__ import annotations

import copy
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Optional


REFERENCE = Path(__file__).with_name("karabiner.json")
LIVE = Path.home() / ".config/karabiner/karabiner.json"
STATE = (
    Path.home()
    / "Library/Application Support/karabiner-linux-mode/karabiner-profile-state.json"
)
DEFAULT_PROFILE = "Linux"


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"{path} does not contain a JSON object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=4, ensure_ascii=False)
            stream.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def backup_live() -> Optional[Path]:
    if not LIVE.exists():
        return None
    suffix = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = LIVE.with_name(f"{LIVE.name}.backup.{suffix}")
    counter = 1
    while backup.exists():
        backup = LIVE.with_name(f"{LIVE.name}.backup.{suffix}.{counter}")
        counter += 1
    shutil.copy2(LIVE, backup)
    return backup


def profiles(config: dict[str, Any]) -> list[dict[str, Any]]:
    value = config.setdefault("profiles", [])
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValueError("Karabiner config has an invalid profiles array")
    return value


def reference_profile(name: str) -> dict[str, Any]:
    candidates = [p for p in profiles(read_json(REFERENCE)) if p.get("name") != "Default"]
    if len(candidates) != 1:
        raise ValueError(f"expected exactly one layout profile in {REFERENCE}")
    result = copy.deepcopy(candidates[0])
    result["name"] = name
    result["selected"] = True
    return result


def comparable(profile: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(profile)
    result.pop("selected", None)
    result["simple_modifications"] = sorted(
        result.get("simple_modifications", []),
        key=lambda item: item.get("from", {}).get("key_code", ""),
    )
    return result


def find_profile(config: dict[str, Any], name: str) -> Optional[dict[str, Any]]:
    found = [item for item in profiles(config) if item.get("name") == name]
    if len(found) > 1:
        raise ValueError(f"Karabiner config contains multiple profiles named {name!r}")
    return found[0] if found else None


def install(name: str) -> int:
    live = read_json(LIVE) if LIVE.exists() else {}
    payload = reference_profile(name)
    existing = find_profile(live, name)

    if STATE.exists():
        state = read_json(STATE)
        if state.get("version") != 1 or state.get("profile_name") != name:
            raise ValueError(
                f"{STATE} owns another or unrecognized profile; uninstall it first"
            )
    else:
        # Adopt profiles installed by releases that predate ownership state.
        legacy_owned = existing is not None and comparable(existing) == comparable(payload)
        selected = next((p.get("name") for p in profiles(live) if p.get("selected")), None)
        state = {
            "version": 1,
            "profile_name": name,
            "target_existed": existing is not None and not legacy_owned,
            "previous_profile": copy.deepcopy(existing) if existing and not legacy_owned else None,
            "previous_selected_profile": selected,
        }

    state["installed_profile"] = payload
    write_json(STATE, state)

    kept = [copy.deepcopy(p) for p in profiles(live) if p.get("name") != name]
    for item in kept:
        item["selected"] = False
    if not any(item.get("name") == "Default" for item in kept):
        kept.insert(0, {"name": "Default", "virtual_hid_keyboard": {"keyboard_type_v2": "ansi"}})
    live["profiles"] = kept + [payload]
    backup = backup_live()
    write_json(LIVE, live)
    if backup:
        print(f"Backed up existing config -> {backup}")
    print(
        f'Installed profile "{name}" '
        f'({len(payload.get("simple_modifications", []))} modifier mappings, '
        f'{len(payload.get("complex_modifications", {}).get("rules", []))} rules)'
    )
    print("Preserved profiles: " + ", ".join(p.get("name", "") for p in kept))
    return 0


def uninstall(requested_name: Optional[str] = None) -> int:
    state = read_json(STATE) if STATE.exists() else None
    name = requested_name or (state.get("profile_name") if state else DEFAULT_PROFILE)
    if state and (state.get("version") != 1 or state.get("profile_name") != name):
        raise ValueError(f"ownership record does not match profile {name!r}")
    if not LIVE.exists():
        print("No live Karabiner config was found; profile unchanged.")
        return 0

    live = read_json(LIVE)
    current = find_profile(live, name)
    if current is None:
        if state:
            raise ValueError(
                f"owned profile {name!r} is missing; refusing a partial uninstall"
            )
        print(f"Karabiner profile {name!r} is already absent.")
        return 0

    installed = state.get("installed_profile") if state else reference_profile(name)
    if not isinstance(installed, dict) or comparable(current) != comparable(installed):
        raise ValueError(
            f"profile {name!r} changed after installation; refusing to remove it"
        )

    restored = state.get("previous_profile") if state and state.get("target_existed") else None
    remaining = [copy.deepcopy(p) for p in profiles(live) if p.get("name") != name]
    if isinstance(restored, dict):
        remaining.append(copy.deepcopy(restored))
    if not remaining:
        remaining = [{"name": "Default", "virtual_hid_keyboard": {"keyboard_type_v2": "ansi"}}]

    wanted = state.get("previous_selected_profile") if state else "Default"
    selected = next((p for p in remaining if p.get("name") == wanted), None)
    selected = selected or next((p for p in remaining if p.get("name") == "Default"), remaining[0])
    for item in remaining:
        item["selected"] = item is selected
    live["profiles"] = remaining

    backup = backup_live()
    write_json(LIVE, live)
    if STATE.exists():
        STATE.unlink()
    if backup:
        print(f"Backed up existing config -> {backup}")
    verb = "Restored previous" if isinstance(restored, dict) else "Removed"
    print(f'{verb} Karabiner profile "{name}"')
    print(f'Profile to activate: {selected.get("name")}')
    return 0


def main() -> int:
    if len(sys.argv) not in {2, 3} or sys.argv[1] not in {"install", "uninstall"}:
        print(f"usage: {Path(sys.argv[0]).name} install PROFILE | uninstall [PROFILE]", file=sys.stderr)
        return 2
    try:
        if sys.argv[1] == "install":
            if len(sys.argv) != 3:
                raise ValueError("install requires a profile name")
            return install(sys.argv[2])
        return uninstall(sys.argv[2] if len(sys.argv) == 3 else None)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
