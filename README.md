# karabiner-linux-mode

Make a Mac keyboard behave like a Linux one, by **physical key position** rather
than by what is printed on the keycaps.

`Ctrl+C` copies in Finder and interrupts in the terminal. `Ctrl+←/→` moves by
word. `Alt+Tab` switches windows. `Ctrl+Alt+←/→` rotates workspaces.

## Notation: [1] [2] [3]

Once you rotate the modifiers, the printed labels are misleading, so everything
here is described by position.

```
        [1]        [2]        [3]        spacebar
PC:    Ctrl      Super       Alt
Mac:  Control    Option    Command
```

Left to right, ignoring `fn`. **Position 1 is the same key on both platforms.**
What differs is what the OS binds to it: Linux puts copy/paste/save on position
1, macOS puts them on position 3.

## The idea

Instead of translating dozens of shortcuts app by app, **rotate the three
modifiers once** so the corner key becomes the one macOS treats as Command:

```
[1]  ->  Command    the "Linux Ctrl" role: copy, paste, save, quit, find
[2]  ->  Control    real Control, for terminal control characters
[3]  ->  Option     the "Linux Alt" role
```

Three lines of config. Every `Cmd` shortcut in every app immediately lands on
`[1]`, with no per-app rules, including webviews, Electron apps and native
dialogs that per-app remapping cannot reach. As a bonus, `Cmd+Tab` sits exactly
where Linux puts `Alt+Tab`.

Everything after the rotation is exception handling:

| Layer | Job |
|---|---|
| Karabiner `simple_modifications` | the rotation, 3 lines |
| Karabiner `complex_modifications` | terminal control characters, windows, 27 rules |
| macOS Keyboard Shortcuts | workspaces and Mission Control, moved to `[1]+[3]`+arrow |
| `~/.zshrc` | 4 `bindkey` lines |
| VS Code `keybindings.json` | 21 bindings |

**The rotation must live in Karabiner, not in the macOS Modifier Keys pane.**
Set in both places it applies twice, and `[1]` ends up as Option. The Karabiner
version also covers every keyboard at once, and lives in this repo where
"Restore Defaults" cannot reach it. The verifier warns if it finds a macOS-level
remap.

**VS Code needs its own bindings** because Karabiner only knows which app is
frontmost, not whether focus is in the editor or the integrated terminal. Those
need opposite behaviour for the same key: `[1]+C` must copy in the editor and
interrupt in the terminal. Only VS Code can tell them apart, using `when`
clauses.

## Install

Requires [Karabiner-Elements](https://karabiner-elements.pqrs.org), `jq`, and
Xcode Command Line Tools.

```sh
git clone https://github.com/Th0masL/karabiner-linux-mode.git
cd karabiner-linux-mode
./install-karabiner-config.sh
```

It lists your Karabiner profiles, asks which to install into (default `Linux`),
runs the macOS checks, then merges the profile. Your other profiles are left
alone and the previous config is backed up.

Then, by hand:

```sh
cat zshrc-snippet.zsh >> ~/.zshrc
cp vscode-keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json
```

The VS Code copy is not automatic because it would overwrite bindings you may
already have.

## Manual macOS settings

The installer cannot set these. The verifier checks them.

| Pane | Setting |
|---|---|
| Keyboard Shortcuts > Modifier Keys | Restore Defaults on *every* keyboard in the dropdown |
| Keyboard Shortcuts > Mission Control | rebind *Mission Control*, *Application windows*, *Move left/right a space* to `[1]+[3]`+arrow |
| Keyboard Shortcuts > Windows | untick the `Halves` group |
| Keyboard Shortcuts > Input Sources | untick both rows |

The `Halves` rows display as `⌃🌐←` and look like they need the Globe key. They
do not. Every arrow key carries the function bit, so `Ctrl+↑` and `fn+Ctrl+↑`
are indistinguishable to macOS. Left enabled, they silently swallow the
`Control`+arrow events Karabiner sends to your terminal, breaking word movement
and history search with no visible cause.

## Checking it

```sh
./verify-macos-setup.sh
```

18 read-only checks across macOS shortcuts, Karabiner, zsh and VS Code. Run it
whenever something stops working. The usual cause is **Restore Defaults** in
Keyboard Shortcuts, which resets every pane at once and is the only part of this
setup not stored in a file you control.

## The mapping

### Apps

| Keys | Action |
|---|---|
| `[1]+C/X/V/A/Z/S/O/N/P/F/W/Q/T` | the usual clipboard and file shortcuts |
| `[1]+←/→` | move by word |
| `[1]+Shift+←/→` | select by word |
| `[1]+Backspace` / `[1]+Del` | delete word left / right |
| `[1]+Tab` / `[1]+Shift+Tab` | next / previous tab |
| `Fn+F1` / `Fn+F3` / `Fn+F5` | Help / Find Next / reload |

### Terminal

| Keys | Action |
|---|---|
| `[1]+C` / `[1]+Z` | interrupt / suspend |
| `[1]+A` / `[1]+E` | start / end of line |
| `[1]+U` / `[1]+K` / `[1]+W` | kill before / after cursor, delete word back |
| `[1]+Backspace` | delete previous word |
| `[1]+R` | reverse history search |
| `[1]+↑/↓` | history search, filtered by what you have typed |
| `[1]+←/→` | word movement |
| `[1]+Shift+C` / `[1]+Shift+V` | copy / paste |
| `[1]+Shift+T` / `[3]+1..9` | new tab / jump to tab N |

### Windows and desktop

| Keys | Action |
|---|---|
| `[3]+Tab` | app switcher |
| `[3]+~` | cycle windows of the current app |
| `[3]+F4` | close window |
| `[2]+L` | lock screen |
| `[1]+[3]+T` | open a terminal |
| `[1]+[3]+←/→` | switch workspace |
| `[1]+[3]+↑` | overview |

Every F-key rule requires `Fn`, so brightness, Mission Control and dictation
still work on a plain press.

## Limitations

* No `Home`, `End`, `Insert` or `PrtSc` on Apple keyboards. `fn+←/→` gives you
  Home/End; `[1]+Shift+3/4` takes a screenshot.
* Moving a window to another workspace has no macOS shortcut at all. It needs a
  tool such as yabai.
* `[1]+D` (EOF) is deliberately not mapped: it is one typo away from closing
  your terminal. EOF stays on `[2]+D`. Add `setopt IGNORE_EOF` to `~/.zshrc` if
  you want it on `[1]` with a guard.
* macOS shortcut settings are not version-controlled, and one "Restore Defaults"
  click wipes them.

## Files

| File | Purpose |
|---|---|
| `generate-karabiner.sh` | source of truth: the tables that build the rules |
| `karabiner.json` | generated output |
| `install-karabiner-config.sh` | list profiles, verify, merge |
| `verify-macos-setup.sh` | 18 read-only checks |
| `vscode-keybindings.json` | reference VS Code config, and what the verifier checks against |
| `zshrc-snippet.zsh` | the four `bindkey` lines |

`karabiner.json` is generated. Edit the tables in `generate-karabiner.sh` and
re-run it rather than hand-editing 1600 lines of nested JSON:

```sh
./generate-karabiner.sh          # rewrite karabiner.json
./generate-karabiner.sh --check  # fail if karabiner.json is stale
./install-karabiner-config.sh    # apply it
```

Each group in the generator carries a comment explaining its **scoping**, which
is the easy thing to get wrong. A wrong scope fails silently: the key just does
something else.

## Credit

Started as a fork of
[rux616/karabiner-windows-mode](https://github.com/rux616/karabiner-windows-mode),
which takes the opposite approach: it leaves the modifiers alone and translates
`Ctrl+<key>` to `Cmd+<key>` app by app, in 59 rules. That works well, but it can
only reach apps identifiable by bundle ID, never webviews or native dialogs.
This repo trades those rules for one rotation plus a few exceptions.

Public domain, as upstream was. See `LICENSE.txt`.
