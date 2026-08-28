#!/usr/bin/env bash
#
# install-karabiner-config.sh [profile-name]
# install-karabiner-config.sh --uninstall-keybindings
# install-karabiner-config.sh --uninstall-editor-keybindings
#
# Installs this repo's Linux-style keyboard layout into Karabiner-Elements.
#
#   1. refuses to install if karabiner.json is stale
#   2. lists your existing Karabiner profiles and asks which to install into
#   3. merges the profile into your existing Karabiner config
#   4. installs Linux-style native macOS text-editing bindings
#   5. safely merges focus-aware VS Code/VSCodium keybindings when detected
#   6. verifies the complete installed setup
#
# The profile is MERGED, not overwritten: any other profiles you already have
# are left untouched. Only a profile with the chosen name is replaced.
#
# A symlink is deliberately not used for karabiner.json -- Karabiner-Elements
# saves it atomically (write temp file, then rename), which replaces a symlink
# with a regular file. Re-run this script after editing the repo copy.
#
# Requires: jq, and Karabiner-Elements.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_CFG="$HERE/karabiner.json"
GENERATOR="$HERE/generate-karabiner.sh"
VERIFY="$HERE/verify-macos-setup.sh"
APPKIT_BINDINGS="$HERE/manage-appkit-keybindings.py"
EDITOR_BINDINGS="$HERE/manage-editor-keybindings.py"
LIVE_CFG="$HOME/.config/karabiner/karabiner.json"
CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
DEFAULT_PROFILE="Linux"

if [[ "${1:-}" == "--uninstall-keybindings" ]]; then
  exec "$APPKIT_BINDINGS" uninstall
fi
if [[ "${1:-}" == "--uninstall-editor-keybindings" ]]; then
  exec "$EDITOR_BINDINGS" uninstall
fi

#-----------------------------------------------------------------------------#
# prerequisites
#-----------------------------------------------------------------------------#
if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<'EOM'
error: jq is required but not installed.

Install it with Homebrew:

    brew install jq

If you do not have Homebrew, see https://brew.sh
EOM
  exit 1
fi

[[ -f "$REPO_CFG" ]] || { echo "error: $REPO_CFG not found" >&2; exit 1; }
[[ -x "$GENERATOR" ]] || { echo "error: $GENERATOR not found or not executable" >&2; exit 1; }
[[ -x "$VERIFY" ]] || { echo "error: $VERIFY not found or not executable" >&2; exit 1; }
[[ -x "$APPKIT_BINDINGS" ]] || { echo "error: $APPKIT_BINDINGS not found or not executable" >&2; exit 1; }
[[ -x "$EDITOR_BINDINGS" ]] || { echo "error: $EDITOR_BINDINGS not found or not executable" >&2; exit 1; }
jq empty "$REPO_CFG" 2>/dev/null || { echo "error: $REPO_CFG is not valid JSON" >&2; exit 1; }
"$GENERATOR" --check

if [[ ! -x "$CLI" ]]; then
  echo "error: karabiner_cli not found. Install Karabiner-Elements first:" >&2
  echo "       https://karabiner-elements.pqrs.org" >&2
  exit 1
fi

#-----------------------------------------------------------------------------#
# 2. list profiles and choose one
#-----------------------------------------------------------------------------#
if [[ -f "$LIVE_CFG" ]] && jq empty "$LIVE_CFG" 2>/dev/null; then
  LIST="$(jq -r '
    (.profiles // [])[]
    | [ .name,
        ((.complex_modifications.rules // []) | length | tostring),
        (if .selected then "*" else "" end) ]
    | @tsv' "$LIVE_CFG")"
else
  LIST=""
fi

NAMES=()
if [[ -n "$LIST" ]]; then
  echo "Karabiner profiles found:"
  while IFS=$'\t' read -r n r s; do
    [[ -z "$n" ]] && continue
    NAMES+=("$n")
    printf '  %d) %-22s %3s rules%s\n' "${#NAMES[@]}" "$n" "$r" \
           "$([[ -n "$s" ]] && echo '   (active)')"
  done <<< "$LIST"
else
  echo "No existing Karabiner profiles found."
fi
echo

if [[ -n "${1:-}" ]]; then
  PROFILE="$1"
elif [[ -t 0 ]]; then
  echo "Enter a number to overwrite that profile, or type a new name."
  printf 'Profile to install into [%s]: ' "$DEFAULT_PROFILE"
  read -r answer
  if [[ -z "$answer" ]]; then
    PROFILE="$DEFAULT_PROFILE"
  elif [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#NAMES[@]} )); then
    PROFILE="${NAMES[$((answer-1))]}"
  else
    PROFILE="$answer"
  fi
else
  PROFILE="$DEFAULT_PROFILE"
fi

if [[ ${#NAMES[@]} -gt 0 ]] && printf '%s\n' "${NAMES[@]}" | grep -qxF "$PROFILE"; then
  echo "Using existing profile: $PROFILE  (its rules will be replaced)"
else
  echo "Creating new profile: $PROFILE"
fi
echo

#-----------------------------------------------------------------------------#
# 3. merge the profile into the live config
#-----------------------------------------------------------------------------#
if [[ -f "$LIVE_CFG" ]]; then
  BACKUP="$LIVE_CFG.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$LIVE_CFG" "$BACKUP"
  echo "Backed up existing config -> $BACKUP"
fi
mkdir -p "$(dirname "$LIVE_CFG")"

# The repo ships a "Default" pass-through profile plus the layout profile; the
# payload is whichever is not the pass-through one.
PAYLOAD="$(jq --arg name "$PROFILE" '
  (.profiles | map(select(.name != "Default")) | .[0])
  | .name = $name
  | .selected = true' "$REPO_CFG")"

if [[ -z "$PAYLOAD" || "$PAYLOAD" == "null" ]]; then
  echo "error: no layout profile found in $REPO_CFG" >&2
  exit 1
fi

BASE="{}"
if [[ -f "$LIVE_CFG" ]] && jq empty "$LIVE_CFG" 2>/dev/null; then
  BASE="$(cat "$LIVE_CFG")"
fi

TMP="$(mktemp)"
jq --arg name "$PROFILE" --argjson payload "$PAYLOAD" '
  . as $live
  | (($live.profiles // [])
      | map(select(.name != $name) | .selected = false)) as $kept
  | (if ($kept | any(.name == "Default")) then $kept
     else [{name: "Default",
            virtual_hid_keyboard: {keyboard_type_v2: "ansi"}}] + $kept end) as $kept2
  | $live | .profiles = ($kept2 + [$payload])
' <<< "$BASE" > "$TMP"

jq empty "$TMP" || { echo "error: produced invalid JSON, aborting" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$LIVE_CFG"

jq -r --arg name "$PROFILE" '
  (.profiles[] | select(.name == $name)) as $p
  | "Installed profile \"\($name)\" (\(($p.simple_modifications // []) | length) modifier mappings, \((($p.complex_modifications.rules) // []) | length) rules)",
    "Preserved profiles: \([.profiles[].name] - [$name] | join(", "))"
' "$LIVE_CFG"

sleep 2
"$CLI" --select-profile "$PROFILE"
echo "Active profile: $("$CLI" --show-current-profile-name)"
echo
"$APPKIT_BINDINGS" install
echo
"$EDITOR_BINDINGS" install
echo
echo "Verifying the installed configuration..."
VERIFY_RC=0
"$VERIFY" "$PROFILE" || VERIFY_RC=$?
if [[ $VERIFY_RC -ne 0 ]]; then
  echo "Installation completed, but verification found settings that still need attention." >&2
  exit "$VERIFY_RC"
fi

echo "Done. Karabiner and editors need no restart; restart native apps for AppKit changes."
