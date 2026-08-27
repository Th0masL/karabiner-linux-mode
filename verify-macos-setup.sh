#!/usr/bin/env bash
#
# verify-macos-setup.sh [profile-name]
#
# Checks the macOS-side settings this keyboard layout depends on. The Karabiner
# rules live in karabiner.json and are version-controlled, but the macOS
# settings are not -- and "Restore Defaults" in System Settings > Keyboard >
# Keyboard Shortcuts wipes every pane at once. This reports what is wrong and
# which pane to fix it in.
#
# READ-ONLY. The helper it compiles links only the two SkyLight *getter*
# symbols; the setter is deliberately not declared, so it cannot change
# anything.
#
# Key positions (a PC-like layout -- the remapping is done by Karabiner):
#   [1] -> Command    [2] -> Control    [3] -> Option
#   [4] -> Option     [5] -> Control
#
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<'EOM'
error: jq is required but not installed.

Install it with Homebrew:

    brew install jq

If you do not have Homebrew, see https://brew.sh
EOM
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
LIVE="$HOME/.config/karabiner/karabiner.json"
PROFILE="${1:-Linux}"
PASS=0; FAIL=0; WARN=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n        -> %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n        -> %s\n' "$1" "$2"; WARN=$((WARN+1)); }

HELPER_DIR="${TMPDIR:-/tmp}/karabiner-verify.$(id -u)"
HELPER="$HELPER_DIR/shk-readonly"
build_helper() {
  [[ -x "$HELPER" ]] && return 0
  command -v clang >/dev/null 2>&1 || return 1
  mkdir -p "$HELPER_DIR"
  cat > "$HELPER_DIR/shk.c" <<'CEOF'
/* READ-ONLY: only the getters are declared, so this binary cannot write. */
#include <stdio.h>
#include <stdbool.h>
#include <CoreGraphics/CoreGraphics.h>
extern bool    CGSIsSymbolicHotKeyEnabled(int hk);
extern CGError CGSGetSymbolicHotKeyValue(int hk, unsigned short *ke,
                                         unsigned short *vk, unsigned int *mods);
int main(void) {
  for (int i = 0; i < 512; i++) {
    unsigned short ke = 0, vk = 0; unsigned int m = 0;
    if (CGSGetSymbolicHotKeyValue(i, &ke, &vk, &m) != kCGErrorSuccess) continue;
    if (vk == 0xFFFF) continue;                    /* 0xFFFF = no key assigned */
    printf("%d\t%d\t%u\t0x%06x\n", i, CGSIsSymbolicHotKeyEnabled(i) ? 1 : 0, vk, m);
  }
  return 0;
}
CEOF
  clang -O2 -o "$HELPER" "$HELPER_DIR/shk.c" \
        -F/System/Library/PrivateFrameworks \
        -framework SkyLight -framework CoreGraphics 2>/dev/null
}

echo
echo "=== macOS setup check (profile: $PROFILE) ==="
echo
echo "[1/6] Keyboard Shortcuts"

if ! build_helper; then
  warn "cannot read macOS keyboard shortcuts" \
       "the read-only helper did not compile; ensure Xcode Command Line Tools are installed and compatible with this macOS version"
  DUMP=""
else
  DUMP="$("$HELPER")"
  if [[ -z "$DUMP" ]]; then
    warn "macOS keyboard shortcut query returned no data" \
         "the private SkyLight getter may have changed; shortcut checks were skipped"
  fi
fi

if [[ -n "$DUMP" ]]; then
  # THE CRITICAL CHECK. Inside terminals Karabiner turns [1]+arrow into
  # Control+arrow. If any macOS shortcut owns a plain Control+arrow, the
  # WindowServer eats Karabiner's own output and terminal word movement and
  # history search stop working. Mask 0x840000 = control + function; arrow keys
  # always set the function bit, so this is how a plain [2]+arrow looks.
  # IDs 192-206 are excluded: that range is modal -- it only matches while a
  # particular macOS UI is on screen, so it never intercepts normal typing. The
  # giveaway is that 192-195 are bound to BARE arrows, which could not possibly
  # be global or you could not type at all. Verified empirically: terminal word
  # movement works with 199/200 enabled.
  BLOCKERS="$(awk -F'\t' '$2==1 && $3>=123 && $3<=126 && $4=="0x840000" \
                          && !($1>=192 && $1<=206) {printf "%s ", $1}' <<< "$DUMP")"
  if [[ -z "${BLOCKERS// /}" ]]; then
    ok "nothing is bound to a plain [2]+arrow (terminal arrows are safe)"
  else
    bad "macOS shortcuts own a plain [2]+arrow: ${BLOCKERS% }" \
        "these break terminal word movement and history search. Untick them in Keyboard Shortcuts: the Mission Control pane, and the 'Halves' group in the Windows pane"
  fi

  for id in 60 61; do
    st="$(awk -F'\t' -v i="$id" '$1==i {print $2}' <<< "$DUMP")"
    lbl=$([[ $id == 60 ]] && echo "[2]+Space" || echo "[2]+[3]+Space")
    if [[ "$st" == "1" ]]; then
      bad "input-source switching is enabled on $lbl" \
          "untick both rows in Keyboard Shortcuts > Input Sources"
    elif [[ -n "$st" ]]; then
      ok "input-source switching disabled ($lbl is free)"
    fi
  done

  # Window management is expected on [1]+[3]+arrow (0x980000 = cmd+opt+fn).
  check_wm() {
    local id="$1" label="$2" expected_vk="$3" st vk mods
    st="$(awk -F'\t' -v i="$id" '$1==i {print $2}' <<< "$DUMP")"
    vk="$(awk -F'\t' -v i="$id" '$1==i {print $3}' <<< "$DUMP")"
    mods="$(awk -F'\t' -v i="$id" '$1==i {print $4}' <<< "$DUMP")"
    if [[ -z "$st" ]]; then
      warn "$label not found" "expected on [1]+[3]+arrow"
    elif [[ "$st" == "1" && "$mods" == "0x980000" && "$vk" == "$expected_vk" ]]; then
      ok "$label on [1]+[3]+arrow"
    elif [[ "$st" != "1" ]]; then
      warn "$label is disabled" "re-enable it in Keyboard Shortcuts > Mission Control"
    else
      warn "$label is on an unexpected combination (key code $vk, modifiers $mods)" \
           "expected key code $expected_vk with [1]+[3]"
    fi
  }
  check_wm 32 "Mission Control" 126
  check_wm 33 "Application windows" 125
  check_wm 79 "Move left a space" 123
  check_wm 81 "Move right a space" 124
fi

echo
echo "[2/6] Modifier Keys at the macOS level"
# This layout remaps [1] through [5] in Karabiner. A macOS-level remap on
# top of that applies TWICE -- [1] becomes Command (macOS), then Karabiner
# rotates it again to Option -- and both configs look correct in isolation,
# which makes it painful to diagnose.
#
# A custom setup is legitimate: you may deliberately prefer doing the rotation
# in System Settings and stripping it from karabiner.json. So these are
# warnings, not failures. The point is that you know it is there.
#
# Storage varies across macOS versions and keyboard types. The persisted check
# below inspects modifiermapping keys inside every ByHost plist rather than
# assuming the mapping appears in a plist filename.

KARABINER_ROT=0
if [[ -f "$LIVE" ]] && jq empty "$LIVE" 2>/dev/null; then
  KARABINER_ROT="$(jq -r --arg n "$PROFILE" \
    '[(.profiles // [])[] | select(.name == $n) | (.simple_modifications // []) | length][0] // 0' "$LIVE")"
fi

MACOS_REMAP=0
HID="$(hidutil property --get "UserKeyMapping" 2>/dev/null)"
if [[ -n "$HID" && "$HID" != "(null)" ]]; then
  MACOS_REMAP=1
  warn "a hidutil-level key remapping is active" \
       "clear it with hidutil, or keep it if it is deliberate"
else
  ok "no hidutil-level key remapping"
fi
PERSISTED_REMAPS=""
STALE_REMAPS=""
ACTIVE_HANDLER_IDS="$(ioreg -l -w0 2>/dev/null \
  | awk -F'= ' '/"alt_handler_id" = [0-9]+/ {print $2}' \
  | sort -u)"
while IFS= read -r plist; do
  while IFS= read -r mapping_key; do
    if /usr/libexec/PlistBuddy -c "Print :$mapping_key" "$plist" 2>/dev/null \
       | awk '
           /Dict \{/ {src = dst = ""}
           /HIDKeyboardModifierMappingSrc =/ {src = $3}
           /HIDKeyboardModifierMappingDst =/ {dst = $3}
           /^[[:space:]]*}/ {
             if (src != "" && dst != "" && src != dst) different = 1
           }
           END {exit !different}
         '; then
      # alt_handler_id values are assigned to currently attached HID handlers.
      # System Settings can leave old entries behind after a keyboard is
      # disconnected; those cannot affect input and Restore Defaults cannot
      # remove them because the keyboard no longer appears in the dropdown.
      if [[ "$mapping_key" == *alt_handler_id-* ]] \
         && ! grep -qxF "${mapping_key##*-}" <<< "$ACTIVE_HANDLER_IDS"; then
        STALE_REMAPS+="${STALE_REMAPS:+, }$mapping_key"
      else
        PERSISTED_REMAPS+="${PERSISTED_REMAPS:+, }$mapping_key"
      fi
    fi
  done < <(plutil -p "$plist" 2>/dev/null \
            | sed -n 's/^  "\(com\.apple\.keyboard\.modifiermapping\.[^"]*\)" =>.*/\1/p')
done < <(find "$HOME/Library/Preferences/ByHost" -type f -name '*.plist' 2>/dev/null)

if [[ -n "$PERSISTED_REMAPS" ]]; then
  MACOS_REMAP=1
  warn "per-keyboard Modifier Keys remapping is persisted: $PERSISTED_REMAPS" \
       "Keyboard Shortcuts > Modifier Keys > Restore Defaults, for EVERY keyboard in the dropdown (including disconnected keyboards)"
else
  if [[ -n "$STALE_REMAPS" ]]; then
    ok "no active per-keyboard Modifier Keys remap (ignored stale: $STALE_REMAPS)"
  else
    ok "no per-keyboard Modifier Keys remap detected (best-effort on macOS 26+)"
  fi
fi

if [[ "$MACOS_REMAP" == "1" && "$KARABINER_ROT" != "0" ]]; then
  warn "macOS modifier remapping and Karabiner rotation were both found" \
       "on an affected keyboard they compose, rotating [1] twice. Restore defaults for every keyboard unless this is deliberate"
elif [[ "$MACOS_REMAP" == "1" ]]; then
  warn "the rotation looks like it is done at the macOS level, not in Karabiner" \
       "supported, but not what this repo ships. The rules assume [1]=Command, [2]/[5]=Control, [3]/[4]=Option"
elif [[ "$KARABINER_ROT" == "5" ]]; then
  ok "the five-position remapping is done in Karabiner only, as intended"
elif [[ "$KARABINER_ROT" == "0" ]]; then
  warn "no modifier rotation found in either place" \
       "without it [1] is still Control and almost nothing in this layout works"
else
  warn "Karabiner has $KARABINER_ROT modifier remappings, expected 5" \
       "a partial rotation behaves unpredictably"
fi
echo
echo "[3/6] Karabiner-Elements"
CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
if [[ ! -x "$CLI" ]]; then
  bad "Karabiner-Elements is not installed" "https://karabiner-elements.pqrs.org"
else
  if pgrep -qf karabiner_console_user_server; then
    ok "Karabiner daemon running"
  else
    bad "Karabiner daemon is not running" \
        "grant Input Monitoring and enable the driver extension"
  fi
  cur="$("$CLI" --show-current-profile-name 2>/dev/null)"
  if [[ "$cur" == "$PROFILE" ]]; then
    ok "active profile is '$PROFILE'"
  else
    warn "active profile is '$cur'" "expected '$PROFILE'"
  fi
fi
if [[ -f "$LIVE" ]] && jq empty "$LIVE" 2>/dev/null; then
  actual="$(jq -S -c --arg name "$PROFILE" '
    [(.profiles // [])[] | select(.name == $name)][0] // null
    | if . == null then null else
        del(.selected)
        | .simple_modifications = ((.simple_modifications // []) | sort_by(.from.key_code))
      end' "$LIVE")"
  expected="$(jq -S -c --arg name "$PROFILE" '
    [(.profiles // [])[] | select(.name != "Default")][0] // null
    | if . == null then null else
        .name = $name
        | del(.selected)
        | .simple_modifications = ((.simple_modifications // []) | sort_by(.from.key_code))
      end' "$HERE/karabiner.json")"
  if [[ "$actual" == "null" ]]; then
    bad "profile '$PROFILE' is not in the live config" "run ./install-karabiner-config.sh"
  elif [[ "$expected" == "null" ]]; then
    bad "reference layout profile is missing from $HERE/karabiner.json" \
        "regenerate karabiner.json before verifying"
  elif [[ "$actual" == "$expected" ]]; then
    rot="$(jq '(.simple_modifications // []) | length' <<< "$actual")"
    nrules="$(jq '(.complex_modifications.rules // []) | length' <<< "$actual")"
    ok "profile '$PROFILE' exactly matches the repository ($rot modifier mappings, $nrules rules)"
  else
    bad "profile '$PROFILE' differs from the repository layout" \
        "run ./install-karabiner-config.sh to replace the drifted profile"
  fi
else
  warn "could not read the live Karabiner config" "is $LIVE valid JSON?"
fi

echo
echo "[4/6] AppKit key bindings"
APPKIT_BINDINGS="$HERE/manage-appkit-keybindings.py"
if [[ ! -x "$APPKIT_BINDINGS" ]]; then
  warn "AppKit key-binding manager is missing" \
       "expected executable at $APPKIT_BINDINGS"
elif APPKIT_STATUS="$("$APPKIT_BINDINGS" check 2>&1)"; then
  ok "$APPKIT_STATUS"
else
  warn "$APPKIT_STATUS" "run ./install-karabiner-config.sh"
fi

echo
echo "[5/6] zsh key bindings"
BOUND="$(zsh -ic '
  bindkey "^[[1;5A"
  bindkey "^[[1;5B"
  bindkey "^[[1;5C"
  bindkey "^[[1;5D"' 2>/dev/null)"
check_zsh_binding() {
  local sequence="$1" label="$2" widget_pattern="$3"
  if grep -F "$sequence" <<< "$BOUND" | grep -Eq "$widget_pattern"; then
    ok "$label is bound"
  else
    warn "$label is not correctly bound in zsh" \
         "append the lines from $HERE/zshrc-snippet.zsh to ~/.zshrc"
  fi
}
check_zsh_binding '"^[[1;5A"' "[1]+Up history prefix search" \
                  'history-beginning-search-backward(-end)?$'
check_zsh_binding '"^[[1;5B"' "[1]+Down history prefix search" \
                  'history-beginning-search-forward(-end)?$'
check_zsh_binding '"^[[1;5C"' "[1]+Right word movement" 'forward-word$'
check_zsh_binding '"^[[1;5D"' "[1]+Left word movement" 'backward-word$'

echo
echo "[6/6] VS Code and VSCodium"
# These are apps Karabiner cannot fully handle: it only sees which app is
# frontmost, not whether focus is in the editor or the integrated terminal, and
# those need opposite behaviour for the same keys. So VS Code carries its own
# bindings, scoped with "when" clauses. vscode-keybindings.json in this repo is
# the reference copy.
REF="$HERE/vscode-keybindings.json"
EDITOR_MANAGER="$HERE/manage-editor-keybindings.py"
# Strip JSONC comments and trailing commas while preserving comment-like text
# inside strings. Perl ships with the macOS versions supported by this project.
strip_jsonc() {
  perl -0777 -pe '
    s~("(?:\\.|[^"\\])*")|//[^\r\n]*|/\*.*?\*/~$1 // ""~gse;
    s~("(?:\\.|[^"\\])*")|,(\s*[}\]])~$1 // $2~gse;
  ' "$1"
}

check_code_bindings() {
  local label="$1" config="$2" n MISSING leak
  if [[ ! -f "$config" ]]; then
    warn "no $label keybindings.json" \
         "copy $REF to \"$config\" (skip if you do not use $label)"
    return
  elif ! strip_jsonc "$config" | jq empty 2>/dev/null; then
    bad "$label keybindings.json does not parse" "$label silently ignores the whole file"
    return
  fi

  n="$(strip_jsonc "$config" | jq 'length')"
  ok "$label keybindings.json is valid ($n bindings)"

  # Expectations are DERIVED from vscode-keybindings.json rather than duplicated
  # here, so adding a binding to the reference automatically extends this check.
  if [[ ! -f "$REF" ]]; then
    warn "no reference file at $REF" "cannot check which bindings are expected"
  else
    MISSING="$(jq -rn \
      --argjson ref "$(strip_jsonc "$REF" | jq '[.[] | {key, command, args, when}]')" \
      --argjson liv "$(strip_jsonc "$config" | jq '[.[] | {key, command, args, when}]')" \
      '($ref - $liv)[] | "\(.key) -> \(.command) (including args and when clause)"')"
    if [[ -z "$MISSING" ]]; then
      ok "$label has all bindings from the reference config"
    else
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '        missing: %s\n' "$line"
      done <<< "$MISSING"
      bad "$label is missing some reference bindings (listed above)" \
          "copy $REF over \"$config\""
    fi
  fi

  # A binding with no "when" applies in the terminal too, which would break
  # SIGINT and friends.
  leak="$(strip_jsonc "$config" | jq -r '[.[] | select(has("when") | not) | .key] | join(", ")')"
  if [[ -z "$leak" ]]; then
    ok "$label bindings are scoped (none leak into the terminal)"
  else
    bad "unscoped $label bindings: $leak" \
        'add a "when" clause, e.g. "editorTextFocus", or they will also fire in the terminal'
  fi
}

check_code_bindings "VS Code" \
  "$HOME/Library/Application Support/Code/User/keybindings.json"
check_code_bindings "VSCodium" \
  "$HOME/Library/Application Support/VSCodium/User/keybindings.json"

if [[ -x "$EDITOR_MANAGER" ]]; then
  if "$EDITOR_MANAGER" check >/dev/null 2>&1; then
    ok "editor keybindings are installer-managed"
  else
    warn "editor keybindings are present but not installer-managed" \
         "run ./install-karabiner-config.sh to adopt them safely"
  fi
fi

echo
printf '=== %d passed, %d warnings, %d failures ===\n' "$PASS" "$WARN" "$FAIL"
if [[ $FAIL -gt 0 ]]; then
  cat <<'EOM'

Most failures come from pressing "Restore Defaults" in System Settings >
Keyboard > Keyboard Shortcuts, which resets every pane at once.
EOM
fi
echo
exit $(( FAIL > 0 ? 1 : 0 ))
