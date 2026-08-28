#!/usr/bin/env bash
#
# install-karabiner-config.sh [profile-name]
# install-karabiner-config.sh --uninstall [profile-name]
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
# Requires: Python 3 and Karabiner-Elements.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_CFG="$HERE/karabiner.json"
GENERATOR="$HERE/generate-karabiner"
VERIFY="$HERE/verify-macos-setup.sh"
PROFILE_MANAGER="$HERE/manage-karabiner-profile"
APPKIT_BINDINGS="$HERE/manage-appkit-keybindings"
EDITOR_BINDINGS="$HERE/manage-editor-keybindings"
LIVE_CFG="$HOME/.config/karabiner/karabiner.json"
CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
DEFAULT_PROFILE="Linux"

if [[ "${1:-}" == "--uninstall-keybindings" ]]; then
  exec "$APPKIT_BINDINGS" uninstall
fi
if [[ "${1:-}" == "--uninstall-editor-keybindings" ]]; then
  exec "$EDITOR_BINDINGS" uninstall
fi
if [[ "${1:-}" == "--uninstall" ]]; then
  if (( $# > 2 )); then
    echo "usage: $0 --uninstall [profile-name]" >&2
    exit 2
  fi
  [[ -x "$PROFILE_MANAGER" ]] || { echo "error: $PROFILE_MANAGER not found or not executable" >&2; exit 1; }
  [[ -x "$APPKIT_BINDINGS" ]] || { echo "error: $APPKIT_BINDINGS not found or not executable" >&2; exit 1; }
  [[ -x "$EDITOR_BINDINGS" ]] || { echo "error: $EDITOR_BINDINGS not found or not executable" >&2; exit 1; }
  if [[ -n "${2:-}" ]]; then
    "$PROFILE_MANAGER" uninstall "$2"
  else
    "$PROFILE_MANAGER" uninstall
  fi

  if [[ -f "$LIVE_CFG" ]] && [[ -x "$CLI" ]]; then
    ACTIVE_PROFILE="$("$PROFILE_MANAGER" active)"
    if [[ -n "$ACTIVE_PROFILE" ]]; then
      if "$CLI" --select-profile "$ACTIVE_PROFILE"; then
        echo "Active profile: $ACTIVE_PROFILE"
      else
        echo "warning: profile was removed, but Karabiner could not activate $ACTIVE_PROFILE" >&2
      fi
    fi
  fi

  UNINSTALL_RC=0
  "$APPKIT_BINDINGS" uninstall || UNINSTALL_RC=$?
  "$EDITOR_BINDINGS" uninstall || UNINSTALL_RC=$?

  cat <<'EOM'

Manual cleanup reminders:
  - If you added the four bindkey lines from zshrc-snippet.zsh to ~/.zshrc or
    ~/.bashrc, delete those lines manually.
  - Restore any macOS Keyboard Shortcuts you changed manually if you want the
    original macOS shortcuts back.
EOM
  exit "$UNINSTALL_RC"
fi

#-----------------------------------------------------------------------------#
# prerequisites
#-----------------------------------------------------------------------------#
command -v python3 >/dev/null 2>&1 || {
  echo "error: Python 3 is required but not installed" >&2
  exit 1
}

[[ -f "$REPO_CFG" ]] || { echo "error: $REPO_CFG not found" >&2; exit 1; }
[[ -x "$GENERATOR" ]] || { echo "error: $GENERATOR not found or not executable" >&2; exit 1; }
[[ -x "$VERIFY" ]] || { echo "error: $VERIFY not found or not executable" >&2; exit 1; }
[[ -x "$PROFILE_MANAGER" ]] || { echo "error: $PROFILE_MANAGER not found or not executable" >&2; exit 1; }
[[ -x "$APPKIT_BINDINGS" ]] || { echo "error: $APPKIT_BINDINGS not found or not executable" >&2; exit 1; }
[[ -x "$EDITOR_BINDINGS" ]] || { echo "error: $EDITOR_BINDINGS not found or not executable" >&2; exit 1; }
"$GENERATOR" --check

if [[ ! -x "$CLI" ]]; then
  echo "error: karabiner_cli not found. Install Karabiner-Elements first:" >&2
  echo "       https://karabiner-elements.pqrs.org" >&2
  exit 1
fi

#-----------------------------------------------------------------------------#
# 2. list profiles and choose one
#-----------------------------------------------------------------------------#
if [[ -f "$LIVE_CFG" ]]; then
  LIST="$("$PROFILE_MANAGER" list)"
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
"$PROFILE_MANAGER" install "$PROFILE"

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
