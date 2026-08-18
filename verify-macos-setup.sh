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
# Key positions (a rotated, PC-like layout -- the rotation is done by Karabiner):
#   [1] corner key       -> Command
#   [2] middle key       -> Control
#   [3] next to spacebar -> Option
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
echo "[1/5] Keyboard Shortcuts"

if ! build_helper; then
  warn "cannot read macOS keyboard shortcuts" "clang missing -- run: xcode-select --install"
  DUMP=""
else
  DUMP="$("$HELPER")"
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
    local id="$1" label="$2" st mods
    st="$(awk -F'\t' -v i="$id" '$1==i {print $2}' <<< "$DUMP")"
    mods="$(awk -F'\t' -v i="$id" '$1==i {print $4}' <<< "$DUMP")"
    if [[ -z "$st" ]]; then
      warn "$label not found" "expected on [1]+[3]+arrow"
    elif [[ "$st" == "1" && "$mods" == "0x980000" ]]; then
      ok "$label on [1]+[3]+arrow"
    elif [[ "$st" != "1" ]]; then
      warn "$label is disabled" "re-enable it in Keyboard Shortcuts > Mission Control"
    else
      warn "$label is on an unexpected combination ($mods)" "expected [1]+[3]+arrow"
    fi
  }
  check_wm 32 "Mission Control"
  check_wm 33 "Application windows"
  check_wm 79 "Move left a space"
  check_wm 81 "Move right a space"
fi

echo
echo "[2/5] Modifier Keys at the macOS level"
# This layout does the [1]/[2]/[3] rotation in Karabiner. A macOS-level remap on
# top of that applies TWICE -- [1] becomes Command (macOS), then Karabiner
# rotates it again to Option -- and both configs look correct in isolation,
# which makes it painful to diagnose.
#
# A custom setup is legitimate: you may deliberately prefer doing the rotation
# in System Settings and stripping it from karabiner.json. So these are
# warnings, not failures. The point is that you know it is there.
#
# Caveat: macOS 26 no longer stores this in ~/Library/Preferences/ByHost, so
# detection is best-effort and can miss a remap set through System Settings.

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
if find "$HOME/Library/Preferences/ByHost" -iname '*modifiermapping*' 2>/dev/null | grep -q .; then
  MACOS_REMAP=1
  warn "a per-keyboard Modifier Keys remap is set in System Settings" \
       "Keyboard Shortcuts > Modifier Keys > Restore Defaults, for EVERY keyboard in the dropdown"
else
  ok "no per-keyboard Modifier Keys remap detected (best-effort on macOS 26+)"
fi

if [[ "$MACOS_REMAP" == "1" && "$KARABINER_ROT" != "0" ]]; then
  warn "BOTH macOS and Karabiner are remapping modifiers" \
       "they compose: [1] is rotated twice and lands on the wrong modifier. Pick one place"
elif [[ "$MACOS_REMAP" == "1" ]]; then
  warn "the rotation looks like it is done at the macOS level, not in Karabiner" \
       "supported, but not what this repo ships. The rules assume [1]=Command, [2]=Control, [3]=Option"
elif [[ "$KARABINER_ROT" == "3" ]]; then
  ok "the rotation is done in Karabiner only, as intended"
elif [[ "$KARABINER_ROT" == "0" ]]; then
  warn "no modifier rotation found in either place" \
       "without it [1] is still Control and almost nothing in this layout works"
else
  warn "Karabiner has $KARABINER_ROT modifier rotations, expected 3" \
       "a partial rotation behaves unpredictably"
fi
echo
echo "[3/5] Karabiner-Elements"
CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
if [[ ! -x "$CLI" ]]; then
  bad "Karabiner-Elements is not installed" "https://karabiner-elements.pqrs.org"
else
  pgrep -qf karabiner_console_user_server \
    && ok "Karabiner daemon running" \
    || bad "Karabiner daemon is not running" "grant Input Monitoring and enable the driver extension"
  cur="$("$CLI" --show-current-profile-name 2>/dev/null)"
  [[ "$cur" == "$PROFILE" ]] \
    && ok "active profile is '$PROFILE'" \
    || warn "active profile is '$cur'" "expected '$PROFILE'"
fi
if [[ -f "$LIVE" ]] && jq empty "$LIVE" 2>/dev/null; then
  found="$(jq -r --arg name "$PROFILE" '
    [ (.profiles // [])[] | select(.name == $name) ] as $p
    | if ($p | length) == 0 then "MISSING"
      else "\((($p[0].simple_modifications) // []) | length)\t\((($p[0].complex_modifications.rules) // []) | length)"
      end' "$LIVE")"
  if [[ "$found" == "MISSING" ]]; then
    bad "profile '$PROFILE' is not in the live config" "run ./install-karabiner-config.sh"
  else
    rot="${found%%	*}"; nrules="${found##*	}"
    if [[ "$rot" == "3" ]]; then
      ok "the [1]/[2]/[3] rotation is present ($nrules rules loaded)"
    else
      bad "expected 3 modifier rotations, found $rot" "run ./install-karabiner-config.sh"
    fi
  fi
else
  warn "could not read the live Karabiner config" "is $LIVE valid JSON?"
fi

echo
echo "[4/5] zsh key bindings"
BOUND="$(zsh -ic 'bindkey "^[[1;5A"; bindkey "^[[1;5D"' 2>/dev/null)"
grep -q "history-beginning-search" <<< "$BOUND" \
  && ok "[1]+Up/Down history prefix search is bound" \
  || warn "history prefix search is not bound in zsh" \
          "append the lines from $HERE/zshrc-snippet.zsh to ~/.zshrc"
grep -q "backward-word" <<< "$BOUND" \
  && ok "[1]+Left/Right word movement is bound" \
  || warn "word movement is not bound in zsh" \
          "append the lines from $HERE/zshrc-snippet.zsh to ~/.zshrc"

echo
echo "[5/5] VS Code"
# VS Code is the one app Karabiner cannot handle: it only sees which app is
# frontmost, not whether focus is in the editor or the integrated terminal, and
# those need opposite behaviour for the same keys. So VS Code carries its own
# bindings, scoped with "when" clauses. vscode-keybindings.json in this repo is
# the reference copy.
VSC="$HOME/Library/Application Support/Code/User/keybindings.json"
REF="$HERE/vscode-keybindings.json"
strip_jsonc() { sed -e 's|^[[:space:]]*//.*$||' -e 's|[[:space:]]//[^"]*$||' "$1"; }

if [[ ! -f "$VSC" ]]; then
  warn "no VS Code keybindings.json" \
       "copy $REF to \"$VSC\" (skip if you do not use VS Code)"
elif ! strip_jsonc "$VSC" | jq empty 2>/dev/null; then
  bad "keybindings.json does not parse" "VS Code silently ignores the whole file"
else
  n="$(strip_jsonc "$VSC" | jq 'length')"
  ok "keybindings.json is valid ($n bindings)"

  # Expectations are DERIVED from vscode-keybindings.json rather than duplicated
  # here, so adding a binding to the reference automatically extends this check.
  if [[ ! -f "$REF" ]]; then
    warn "no reference file at $REF" "cannot check which bindings are expected"
  else
    MISSING="$(jq -rn \
      --argjson ref "$(strip_jsonc "$REF" | jq '[.[] | {key, command, when}]')" \
      --argjson liv "$(strip_jsonc "$VSC" | jq '[.[] | {key, command, when}]')" \
      '($ref - $liv)[] | "\(.key) -> \(.command)"')"
    if [[ -z "$MISSING" ]]; then
      ok "all bindings from the reference config are present"
    else
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '        missing: %s\n' "$line"
      done <<< "$MISSING"
      bad "some reference bindings are missing (listed above)" \
          "copy $REF over \"$VSC\""
    fi
  fi

  # A binding with no "when" applies in the terminal too, which would break
  # SIGINT and friends.
  leak="$(strip_jsonc "$VSC" | jq -r '[.[] | select(has("when") | not) | .key] | join(", ")')"
  if [[ -z "$leak" ]]; then
    ok "every binding is scoped (none leak into the terminal)"
  else
    bad "unscoped VS Code bindings: $leak" \
        'add a "when" clause, e.g. "editorTextFocus", or they will also fire in the terminal'
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
