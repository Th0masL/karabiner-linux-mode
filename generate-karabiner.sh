#!/usr/bin/env bash
#
# generate-karabiner.sh
#
# Regenerates karabiner.json from the declarative tables below. Edit this file,
# not karabiner.json -- that is a build artifact, and hand-editing 1600 lines of
# nested JSON is how mistakes happen.
#
#   ./generate-karabiner.sh          # rewrite karabiner.json
#   ./generate-karabiner.sh --check  # fail if karabiner.json is out of date
#
# Set TERMINAL_BUNDLE_ID to change what [1]+[3]/[4]+T launches:
#   TERMINAL_BUNDLE_ID=com.apple.Terminal ./generate-karabiner.sh
#
# Key positions:
#   [1] -> Command    [2] -> Control    [3] -> Option
#   [4] -> Option     [5] -> Control
#
# The positional remapping is five simple_modifications; everything else is a
# complex_modification correcting a case the remapping alone gets wrong.
#
# Requires: jq
#
set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required. Install with: brew install jq" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/karabiner.json"
PROFILE_NAME="Linux"
TERMINAL_BUNDLE_ID="${TERMINAL_BUNDLE_ID:-com.googlecode.iterm2}"

# The value is embedded in a Karabiner shell_command, so accept bundle-ID
# characters only. This also catches accidental application names or paths.
if [[ ! "$TERMINAL_BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "error: invalid TERMINAL_BUNDLE_ID: $TERMINAL_BUNDLE_ID" >&2
  exit 1
fi

#=============================================================================#
# SCOPES
#=============================================================================#
TERMINALS='[
  "^com\\.googlecode\\.iterm2$", "^com\\.apple\\.Terminal$",
  "^com\\.mitchellh\\.ghostty$", "^com\\.github\\.wez\\.wezterm$",
  "^com\\.alacritty$", "^io\\.alacritty$",
  "^net\\.kovidgoyal\\.kitty$", "^co\\.zeit\\.hyper$"
]'
# VS Code is excluded from the editing rules on purpose: Karabiner only knows
# which app is frontmost, not whether focus is in the editor or the integrated
# terminal, and those need opposite behaviour for the same key. VS Code handles
# it in keybindings.json where "when" clauses can tell them apart.
EDITORS='["^com\\.microsoft\\.VSCode", "^com\\.vscodium$"]'
BROWSERS='[
  "^com\\.google\\.Chrome$", "^com\\.google\\.Chrome\\.beta$",
  "^com\\.google\\.chrome$",
  "^org\\.mozilla\\.firefox$", "^org\\.mozilla\\.nightly$",
  "^com\\.brave\\.Browser$", "^com\\.apple\\.Safari$"
]'
SUBLIME='["^com\\.sublimetext\\.[0-9]+$"]'

IF_TERM="$(jq -c -n --argjson t "$TERMINALS" \
  '[{type:"frontmost_application_if", bundle_identifiers:$t}]')"
IF_BROWSER="$(jq -c -n --argjson b "$BROWSERS" \
  '[{type:"frontmost_application_if", bundle_identifiers:$b}]')"
IF_DOCUMENT_APPS="$(jq -c -n --argjson b "$BROWSERS" --argjson s "$SUBLIME" \
  '[{type:"frontmost_application_if", bundle_identifiers:($b + $s)}]')"
UNLESS_TERM_EDITOR="$(jq -c -n --argjson t "$TERMINALS" --argjson e "$EDITORS" \
  '[{type:"frontmost_application_unless", bundle_identifiers:($t + $e)}]')"
# Terminals only. Used where VS Code should be INCLUDED because it has no
# competing terminal-vs-editor case and no binding of its own to catch the key.
UNLESS_TERM="$(jq -c -n --argjson t "$TERMINALS" \
  '[{type:"frontmost_application_unless", bundle_identifiers:$t}]')"
ANYWHERE='[]'

#=============================================================================#
# BUILDERS
#=============================================================================#
RULES="$(mktemp)"; trap 'rm -f "$RULES"' EXIT

# man <from_key> <from_mods> <to_key> <to_mods> <conditions_json>
# mods are "+"-separated, or "" for none.
man() {
  jq -c -n --arg fk "$1" --arg fm "$2" --arg tk "$3" --arg tm "$4" --argjson c "$5" '
    {type: "basic"}
    + (if ($c | length) > 0 then {conditions: $c} else {} end)
    + {from: ({key_code: $fk}
              + (if $fm == "" then {} else {modifiers: {mandatory: ($fm | split("+"))}} end))}
    + {to: [ ({key_code: $tk}
              + (if $tm == "" then {} else {modifiers: ($tm | split("+"))} end)) ]}'
}

# shell_man <from_key> <from_mods> <command> <conditions_json>
shell_man() {
  jq -c -n --arg fk "$1" --arg fm "$2" --arg cmd "$3" --argjson c "$4" '
    {type: "basic"}
    + (if ($c | length) > 0 then {conditions: $c} else {} end)
    + {from: {key_code: $fk, modifiers: {mandatory: ($fm | split("+"))}}}
    + {to: [{shell_command: $cmd}]}'
}

# escape_man <from_key> <from_mods> <following_key> <conditions_json>
# Emits an ESC-prefixed terminal command without depending on whether a
# terminal is configured to treat Option as Meta.
escape_man() {
  jq -c -n --arg fk "$1" --arg fm "$2" --arg tk "$3" --argjson c "$4" '
    {type: "basic"}
    + (if ($c | length) > 0 then {conditions: $c} else {} end)
    + {from: {key_code: $fk, modifiers: {mandatory: ($fm | split("+"))}}}
    + {to: [{key_code: "escape"}, {key_code: $tk}]}'
}

# forward_delete_man <from_key> <from_mods> <conditions_json>
# Emits the standard xterm Forward Delete sequence: ESC [ 3 ~.
forward_delete_man() {
  jq -c -n --arg fk "$1" --arg fm "$2" --argjson c "$3" '
    {type: "basic"}
    + (if ($c | length) > 0 then {conditions: $c} else {} end)
    + {from: {key_code: $fk, modifiers: {mandatory: ($fm | split("+"))}}}
    + {to: [
        {key_code: "escape"},
        {key_code: "open_bracket"},
        {key_code: "3"},
        {key_code: "grave_accent_and_tilde", modifiers: ["left_shift"]}
      ]}'
}

# rule <description> <manipulator-json>...
rule() {
  local desc="$1"; shift
  printf '%s\n' "$@" | jq -c -s --arg d "$desc" '{description: $d, manipulators: .}' >> "$RULES"
}

#=============================================================================#
# 1. TERMINAL -- control characters back onto [1]
#
# The remapping puts real Control on [2] and [5], but Linux expects control
# characters on [1]. Inside terminal apps, translate them back.
#=============================================================================#
while read -r key meaning; do
  [[ -z "${key:-}" || "$key" == \#* ]] && continue
  upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  rule "terminal: [1]+${upper} sends ^${upper} ($meaning)" \
       "$(man "$key" command "$key" left_control "$IF_TERM")"
done <<'TABLE'
c   interrupt
z   suspend
d   delete character / EOF
l   clear screen
y   yank killed text
g   cancel current input
t   transpose characters
p   previous history entry
n   next history entry
b   move one character left
f   move one character right
a   start of line
e   end of line
u   kill before cursor
k   kill after cursor
w   delete word back
r   reverse history search
TABLE

# Linux Ctrl+Delete deletes the next word. ESC-d is the standard Emacs-mode
# shell command for that action and works independently of terminal settings.
# Keep this before the less-specific [1]+Backspace rule below.
rule "terminal: [1]+Fn+Backspace deletes the next word" \
     "$(escape_man delete_or_backspace command+fn d "$IF_TERM")"

rule "terminal: Fn+Backspace sends Forward Delete" \
     "$(forward_delete_man delete_or_backspace fn "$IF_TERM")"

# Linux deletes a previous word with Ctrl+Backspace in a terminal; ^W is the
# readline equivalent. VS Code's keybindings.json does the same.
rule "terminal: [1]+Backspace deletes the previous word" \
     "$(man delete_or_backspace command w left_control "$IF_TERM")"

rule "terminal: [1]+Shift+C copies" \
     "$(man c command+shift c left_command "$IF_TERM")"
rule "terminal: [1]+Shift+V pastes" \
     "$(man v command+shift v left_command "$IF_TERM")"

#=============================================================================#
# 2. TERMINAL -- navigation
#
# Arrows become Control+arrow, which a terminal transmits as the xterm escape
# sequences that zshrc-snippet.zsh binds (^[[1;5A .. ^[[1;5D).
#=============================================================================#
rule "terminal: [1]+arrows for history search and word movement" \
     "$(man up_arrow    command up_arrow    left_control "$IF_TERM")" \
     "$(man down_arrow  command down_arrow  left_control "$IF_TERM")" \
     "$(man left_arrow  command left_arrow  left_control "$IF_TERM")" \
     "$(man right_arrow command right_arrow left_control "$IF_TERM")"

# A compact Apple keyboard produces Home/End for Fn+Left/Right, but terminal
# shells do not consistently bind those key codes. Ctrl+A/E are the portable
# line-start/line-end commands in both Bash and Zsh and need no dotfile setup.
rule "terminal: Fn+Left/Right moves to the start/end of the command line" \
     "$(man left_arrow  fn a left_control "$IF_TERM")" \
     "$(man right_arrow fn e left_control "$IF_TERM")"

# GNOME Terminal uses Shift+Home/End to scroll to the top/bottom of scrollback.
# Terminal.app and iTerm2 expose the same actions as Command+Home/End.
rule "terminal: Shift+Fn+Left/Right scrolls to the top/bottom" \
     "$(man left_arrow  fn+shift home left_command "$IF_TERM")" \
     "$(man right_arrow fn+shift end  left_command "$IF_TERM")"

rule "terminal: [1]+Tab / [1]+Shift+Tab cycles tabs" \
     "$(man tab command       close_bracket left_command+left_shift "$IF_TERM")" \
     "$(man tab command+shift open_bracket  left_command+left_shift "$IF_TERM")"

rule "terminal: [1]+Shift+T opens a new tab" \
     "$(man t command+shift t left_command "$IF_TERM")"

TAB_MANS=()
for n in 1 2 3 4 5 6 7 8 9; do
  TAB_MANS+=("$(man "$n" option "$n" left_command "$IF_TERM")")
done
rule "terminal: [3]/[4]+1..9 jumps to a tab" "${TAB_MANS[@]}"

#=============================================================================#
# 3. TEXT EDITING -- everywhere except terminals and VS Code
#=============================================================================#
rule "editing: [1]+arrows move by word" \
     "$(man left_arrow  command left_arrow  left_option "$UNLESS_TERM_EDITOR")" \
     "$(man right_arrow command right_arrow left_option "$UNLESS_TERM_EDITOR")"

rule "editing: [1]+Shift+arrows select by word" \
     "$(man left_arrow  command+shift left_arrow  left_option+left_shift "$UNLESS_TERM_EDITOR")" \
     "$(man right_arrow command+shift right_arrow left_option+left_shift "$UNLESS_TERM_EDITOR")"

# Fn+Backspace becomes Forward-Delete only after Karabiner's complex rules have
# run, so browsers need an explicit pre-conversion rule for compact keyboards.
# Native AppKit editors use the equivalent DefaultKeyBinding.dict entry.
rule "editing: [1]+Fn+Backspace deletes the next word in browsers" \
     "$(man delete_or_backspace command+fn delete_forward left_option "$IF_BROWSER")"

rule "editing: [1]+Backspace / [1]+Del delete a word" \
     "$(man delete_or_backspace command delete_or_backspace left_option "$UNLESS_TERM_EDITOR")" \
     "$(man delete_forward      command delete_forward      left_option "$UNLESS_TERM_EDITOR")"

# DefaultKeyBinding.dict handles native AppKit editors. Browsers and Sublime do
# not use AppKit text bindings, so translate compact-keyboard Ctrl+Home/End to
# their native document-boundary shortcuts here. VS Code/VSCodium remain in
# their focus-aware keybindings files so integrated terminals are not affected.
rule "editing: [1]+Fn+Left/Right moves to the document start/end in browsers and Sublime" \
     "$(man left_arrow  command+fn       up_arrow   left_command            "$IF_DOCUMENT_APPS")" \
     "$(man right_arrow command+fn       down_arrow left_command            "$IF_DOCUMENT_APPS")" \
     "$(man left_arrow  command+fn+shift up_arrow   left_command+left_shift "$IF_DOCUMENT_APPS")" \
     "$(man right_arrow command+fn+shift down_arrow left_command+left_shift "$IF_DOCUMENT_APPS")"

# Scoped to non-terminals only, NOT excluding VS Code: VS Code has no cmd+tab
# binding, so excluding it would leak through to the macOS app switcher instead
# of cycling editor tabs. Control+Tab is VS Code's own "next editor".
rule "editing: [1]+Tab / [1]+Shift+Tab cycles tabs" \
     "$(man tab command       tab left_control            "$UNLESS_TERM")" \
     "$(man tab command+shift tab left_control+left_shift "$UNLESS_TERM")"

#=============================================================================#
# 4. WINDOWS AND DESKTOP
#
# "Backtick" is the unshifted key above Tab (grave_accent_and_tilde). Named
# rather than written literally: a backtick breaks markdown code spans and is
# command substitution inside a double-quoted shell string.
#=============================================================================#
rule "window: [3]/[4]+Tab switches applications" \
     "$(man tab option       tab left_command            "$ANYWHERE")" \
     "$(man tab option+shift tab left_command+left_shift "$ANYWHERE")"

rule "window: [3]/[4]+Backtick cycles windows of the current application" \
     "$(man grave_accent_and_tilde option       grave_accent_and_tilde left_command            "$ANYWHERE")" \
     "$(man grave_accent_and_tilde option+shift grave_accent_and_tilde left_command+left_shift "$ANYWHERE")"

rule "window: [3]/[4]+F4 closes the current tab/window" \
     "$(man f4 option w left_command "$ANYWHERE")"

# macOS locks with control+command+Q.
rule "window: [2]/[5]+L locks the screen" \
     "$(man l control q left_control+left_command "$ANYWHERE")"

rule "window: [1]+[3]/[4]+T opens the configured terminal" \
     "$(shell_man t command+option "open -b $TERMINAL_BUNDLE_ID" "$ANYWHERE")"

#=============================================================================#
# 5. FUNCTION KEYS
#
# All require Fn, so every native F<N> function (brightness, Mission Control,
# dictation) still works on a plain press.
#=============================================================================#
rule "fkeys: Fn+F1 opens the Help menu" \
     "$(man f1 fn slash left_command+left_shift "$UNLESS_TERM_EDITOR")"
rule "fkeys: Fn+F3 finds next" \
     "$(man f3 fn g left_command "$UNLESS_TERM_EDITOR")"
rule "fkeys: Fn+F5 reloads the page" \
     "$(man f5 fn r left_command "$IF_BROWSER")"

#=============================================================================#
# ASSEMBLE
#=============================================================================#
NEW="$(jq -s --arg name "$PROFILE_NAME" '
  {
    profiles: [
      { name: "Default",
        virtual_hid_keyboard: {keyboard_type_v2: "ansi"} },
      { name: $name,
        selected: true,
        virtual_hid_keyboard: {keyboard_type_v2: "ansi"},
        simple_modifications: [
          {from: {key_code: "left_control"}, to: [{key_code: "left_command"}]},
          {from: {key_code: "left_option"},  to: [{key_code: "left_control"}]},
          {from: {key_code: "left_command"}, to: [{key_code: "left_option"}]},
          # Mirror the Linux Alt and Super positions on the right. Apple
          # keyboards have no sixth/right-Control key, so there is no
          # right-side equivalent of [1].
          {from: {key_code: "right_command"}, to: [{key_code: "right_option"}]},
          {from: {key_code: "right_option"},  to: [{key_code: "right_control"}]}
        ],
        complex_modifications: {rules: .}
      }
    ]
  }' "$RULES")"

if [[ "${1:-}" == "--check" ]]; then
  if diff <(jq -S . <<< "$NEW") <(jq -S . "$OUT") >/dev/null 2>&1; then
    echo "karabiner.json is up to date"
    exit 0
  fi
  echo "karabiner.json is OUT OF DATE -- run ./generate-karabiner.sh" >&2
  diff <(jq -S . "$OUT") <(jq -S . <<< "$NEW") | head -40 >&2
  exit 1
fi

jq . <<< "$NEW" > "$OUT"
printf '%s\n' "" >> /dev/null
echo "wrote $OUT"
jq -r --arg n "$PROFILE_NAME" '
  .profiles[] | select(.name == $n)
  | "  \((.simple_modifications | length)) modifier mappings",
    "  \((.complex_modifications.rules | length)) rules, \(
        [.complex_modifications.rules[].manipulators[]] | length) manipulators"' "$OUT"
