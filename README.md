# karabiner-linux-mode

Make a Mac keyboard behave like a Linux one, by **physical key position** rather
than by what is printed on the keycaps.

`Ctrl+C` copies in Finder and interrupts in the terminal. `Ctrl+←/→` moves by
word. `Alt+Tab` switches applications. `Ctrl+Alt+←/→` rotates workspaces.

## Notation: [1] [2] [3] [4] [5]

Once you remap the modifiers, the printed labels are misleading, so the five
modifier keys are referred to by position. The brackets mark a modifier
position, so `[4]+1` means "the fourth modifier plus the 1 key".

```
        [1]       [2]        [3]      spacebar      [4]       [5]
PC:    Ctrl      Super       Alt                     Alt     Super
Mac:  Control    Option    Command                 Command   Option
Here: Command   Control    Option                  Option   Control
```

Left to right, ignoring `fn` and the arrow cluster. **Position 1 is the same key
on both platforms.** What differs is what the OS binds to it: Linux puts
copy/paste/save on position 1, macOS puts them on positions 3 and 4.

### The missing sixth key

The left side has three modifier positions; the right side of an Apple keyboard
has only two. The mappings mirror the positions that exist:

| Position | Printed key | Produces | Linux role |
|---|---|---|---|
| `[1]` | Left Control | Command | Ctrl |
| `[2]` | Left Option | Control | Super / real Control |
| `[3]` | Left Command | Option | Alt |
| `[4]` | Right Command | Option | Alt |
| `[5]` | Right Option | Control | Super / real Control |

Thus `[3]` and `[4]` are interchangeable Alt positions, while `[2]` and `[5]`
are interchangeable Super/Control positions. Apple provides no third modifier
key on the right that could mirror `[1]`. Copy/paste/save therefore remain
left-side shortcuts.

## The idea

Instead of translating dozens of shortcuts app by app, **remap the five
modifier positions once** so the corner key becomes the one macOS treats as
Command and both sides follow the Linux positions:

```
[1]  ->  Command    the "Linux Ctrl" role: copy, paste, save, quit, find
[2]/[5]  ->  Control    real Control / the "Linux Super" position
[3]/[4]  ->  Option     the "Linux Alt" role
```

Five lines of config. Every `Cmd` shortcut in every app immediately lands on
`[1]`, with no per-app rules, including webviews, Electron apps and native
dialogs that per-app remapping cannot reach. As a bonus, `Cmd+Tab` sits exactly
where Linux puts `Alt+Tab`.

Everything after the positional remapping is exception handling:

| Layer | Job |
|---|---|
| Karabiner `simple_modifications` | the five positional mappings |
| Karabiner `complex_modifications` | terminal control characters, windows and navigation |
| macOS Keyboard Shortcuts | workspaces and Mission Control, moved to `[1]+[3]`+arrow |
| AppKit `DefaultKeyBinding.dict` | Linux-style navigation, selection and word deletion in native editors |
| `~/.zshrc` | 4 `bindkey` lines |
| VS Code/VSCodium `keybindings.json` | 25 focus-aware bindings |

**The remapping must live in Karabiner, not in the macOS Modifier Keys pane.**
Set in both places it applies twice, and `[1]` ends up as Option. The Karabiner
version also covers every keyboard at once, and lives in this repo where
"Restore Defaults" cannot reach it. The verifier warns if it finds a macOS-level
remap.

**VS Code needs its own bindings** because Karabiner only knows which app is
frontmost, not whether focus is in the editor or the integrated terminal. Those
need opposite behaviour for the same key: `[1]+C` must copy in the editor and
interrupt in the terminal. Only VS Code can tell them apart, using `when`
clauses.

## The full mapping

Every combination this repo touches. The Linux and macOS columns show the
**default** shortcut as printed on the keys; the last column is what you press
after installing.

### Clipboard, files, app-level

These need no rules at all. The positional remapping alone puts them on `[1]`.

| Action | Linux | macOS | Here |
|---|---|---|---|
| Copy | `Ctrl+C` | `Cmd+C` | `[1]+C` |
| Cut | `Ctrl+X` | `Cmd+X` | `[1]+X` |
| Paste | `Ctrl+V` | `Cmd+V` | `[1]+V` |
| Select all | `Ctrl+A` | `Cmd+A` | `[1]+A` |
| Undo | `Ctrl+Z` | `Cmd+Z` | `[1]+Z` |
| Redo | `Ctrl+Shift+Z` | `Cmd+Shift+Z` | `[1]+Shift+Z` |
| Save | `Ctrl+S` | `Cmd+S` | `[1]+S` |
| Open | `Ctrl+O` | `Cmd+O` | `[1]+O` |
| New | `Ctrl+N` | `Cmd+N` | `[1]+N` |
| Print | `Ctrl+P` | `Cmd+P` | `[1]+P` |
| Find | `Ctrl+F` | `Cmd+F` | `[1]+F` |
| Close tab | `Ctrl+W` | `Cmd+W` | `[1]+W` |
| Quit app | `Ctrl+Q` | `Cmd+Q` | `[1]+Q` *(outside terminals)* |
| New tab | `Ctrl+T` | `Cmd+T` | `[1]+T` |
| Reload page | `Ctrl+R` | `Cmd+R` | `[1]+R` |
| Address bar | `Ctrl+L` | `Cmd+L` | `[1]+L` |
| Toggle comment | `Ctrl+/` | `Cmd+/` | `[1]+/` |

### Text navigation

Karabiner rules, because macOS puts these on Option rather than Control.

| Action | Linux | macOS | Here |
|---|---|---|---|
| Move by word | `Ctrl+←/→` | `Option+←/→` | `[1]+←/→` |
| Select by word | `Ctrl+Shift+←/→` | `Option+Shift+←/→` | `[1]+Shift+←/→` |
| Delete previous word | `Ctrl+Backspace` | `Option+Delete` (`⌫`) | `[1]+Backspace` (`[1]+⌫` on a Magic Keyboard) |
| Delete next word | `Ctrl+Delete` | `Fn+Option+Delete` (`⌦`) | `[1]+Delete` (`[1]+Fn+⌫` on a compact Magic Keyboard) |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` | `Ctrl+Tab` | `[1]+Tab` / `[1]+Shift+Tab` |
| Line start / end | `Home` / `End` | `Cmd+←/→` | `Fn+←/→` |
| Document start / end | `Ctrl+Home` / `Ctrl+End` | `Cmd+↑/↓` | `[1]+Fn+←/→` (`[1]+↑/↓` also works) |

The **Here** column uses Linux key names and behaviour, regardless of the Mac
keycap. On a compact Magic Keyboard, the key printed `delete` (`⌫`) occupies the
PC Backspace position, so `[1]+⌫` deletes the previous word. Hold `Fn` with it
to produce the PC Delete key (`⌦`), so `[1]+Fn+⌫` deletes the next word.

### Terminal

Karabiner rules scoped to terminal apps, plus four `bindkey` lines in
`~/.zshrc` for the arrows.

| Action | Linux | macOS | Here |
|---|---|---|---|
| Interrupt | `Ctrl+C` | `Ctrl+C` | `[1]+C` |
| Suspend | `Ctrl+Z` | `Ctrl+Z` | `[1]+Z` |
| Delete character / EOF | `Ctrl+D` | `Ctrl+D` | `[1]+D` |
| Clear screen | `Ctrl+L` | `Ctrl+L` | `[1]+L` |
| Start / end of line | `Ctrl+A` / `Ctrl+E` | `Ctrl+A` / `Ctrl+E` | `[1]+A` / `[1]+E` |
| Kill before / after cursor | `Ctrl+U` / `Ctrl+K` | `Ctrl+U` / `Ctrl+K` | `[1]+U` / `[1]+K` |
| Yank killed text | `Ctrl+Y` | `Ctrl+Y` | `[1]+Y` |
| Cancel current input | `Ctrl+G` | `Ctrl+G` | `[1]+G` |
| Transpose characters | `Ctrl+T` | `Ctrl+T` | `[1]+T` |
| Insert next key literally | `Ctrl+V` | `Ctrl+V` | `[1]+V` |
| Delete previous character | `Ctrl+H` | `Ctrl+H` | `[1]+H` |
| Pause / resume terminal output | `Ctrl+S` / `Ctrl+Q` | `Ctrl+S` / `Ctrl+Q` | `[1]+S` / `[1]+Q` |
| Delete word back | `Ctrl+W` | `Ctrl+W` | `[1]+W` |
| Delete word back | `Ctrl+Backspace` | `Option+Delete` (`⌫`) | `[1]+Backspace` (`[1]+⌫` on a Magic Keyboard) |
| Delete word forward | `Ctrl+Delete` | `Meta+D` | `[1]+Fn+Backspace` (`[1]+Fn+⌫`) |
| Delete one character forward | `Delete` | `Forward Delete` | `Fn+Backspace` (`Fn+⌫`) |
| Reverse history search | `Ctrl+R` | `Ctrl+R` | `[1]+R` |
| Previous / next history entry | `Ctrl+P` / `Ctrl+N` | `Ctrl+P` / `Ctrl+N` | `[1]+P` / `[1]+N` |
| History prefix search | *(no default)* | *(no default)* | `[1]+↑/↓` |
| Move one character left / right | `Ctrl+B` / `Ctrl+F` | `Ctrl+B` / `Ctrl+F` | `[1]+B` / `[1]+F` |
| Move by word | `Ctrl+←/→` | `Option+←/→` | `[1]+←/→` |
| Start / end of command line | `Home` / `End` | `Ctrl+A` / `Ctrl+E` | `Fn+←/→` |
| Scroll to top / bottom | `Shift+Home` / `Shift+End` | `Cmd+Home` / `Cmd+End` | `Shift+Fn+←/→` |
| Copy | `Ctrl+Shift+C` | `Cmd+C` | `[1]+Shift+C` |
| Paste | `Ctrl+Shift+V` | `Cmd+V` | `[1]+Shift+V` |
| New tab | `Ctrl+Shift+T` | `Cmd+T` | `[1]+Shift+T` |
| Quit terminal application | `Ctrl+Shift+Q` | `Cmd+Q` | `[1]+Shift+Q` |
| Next / previous tab | `Ctrl+PgUp` / `Ctrl+PgDn` | `Cmd+Shift+]` / `Cmd+Shift+[` | `[1]+Tab` / `[1]+Shift+Tab` |
| Jump to tab N | `Alt+1`..`9` | `Cmd+1`..`9` | `[3]+1`..`9` or `[4]+1`..`9` |

### Windows and desktop

Karabiner rules, except the last three, which are macOS Keyboard Shortcuts you
rebind by hand.

| Action | Linux | macOS | Here |
|---|---|---|---|
| App switcher | `Alt+Tab` | `Cmd+Tab` | `[3]+Tab` or `[4]+Tab` |
| Cycle windows of current app | `Alt+Backtick` | `Cmd+Backtick` | `[3]+Backtick` or `[4]+Backtick` |
| Close current tab/window | `Alt+F4` | `Cmd+W` | `[3]+F4` or `[4]+F4` |
| Lock screen | `Super+L` | `Ctrl+Cmd+Q` | `[2]+L` or `[5]+L` |
| Open configured terminal | `Ctrl+Alt+T` | *(no default)* | `[1]+[3]+T` or `[1]+[4]+T` |
| Screenshot | `PrtSc` | `Cmd+Shift+3` | `[1]+Shift+3` |
| Switch workspace | `Ctrl+Alt+←/→` | `Ctrl+←/→` | `[1]+[3]+←/→` or `[1]+[4]+←/→` |
| Overview | `Super` | `Ctrl+↑` | `[1]+[3]+↑` or `[1]+[4]+↑` |
| All windows of current app | *(varies)* | `Ctrl+↓` | `[1]+[3]+↓` or `[1]+[4]+↓` |

### Function keys

Every F-key rule requires `Fn`, so brightness, Mission Control and dictation
still work on a plain press.

| Action | Linux | macOS | Here |
|---|---|---|---|
| Help | `F1` | `Cmd+Shift+/` | `Fn+F1` |
| Find next | `F3` | `Cmd+G` | `Fn+F3` |
| Reload page | `F5` | `Cmd+R` | `Fn+F5` |

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
alone and the previous config is backed up. It also safely merges Linux-style
native editing behavior into `~/Library/KeyBindings/DefaultKeyBinding.dict`.
Restart open native applications such as Notes after installation.

To remove only the installer-managed AppKit bindings and restore any values
that existed before installation:

```sh
./install-karabiner-config.sh --uninstall-keybindings
```

Other custom bindings in that file are preserved. If you change one of the
managed bindings after installation, uninstall preserves your newer value too.

The terminal shortcut opens iTerm2 by default. macOS has no system-wide
"default terminal" setting, so choose another terminal when generating the
configuration by passing its bundle identifier:

```sh
# Apple Terminal
TERMINAL_BUNDLE_ID=com.apple.Terminal ./generate-karabiner.sh

# Ghostty
TERMINAL_BUNDLE_ID=com.mitchellh.ghostty ./generate-karabiner.sh

./install-karabiner-config.sh
```

Use Karabiner-EventViewer's *Frontmost Application* tab to find another
terminal's bundle identifier. Pass the same variable to `--check` when using a
non-default target.

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

24 read-only checks across macOS shortcuts, Karabiner, AppKit, zsh, VS Code and
VSCodium. Run it
whenever something stops working. The usual cause is **Restore Defaults** in
Keyboard Shortcuts, which resets every pane at once and is the only part of this
setup not stored in a file you control.

## Limitations

* No dedicated `Home`, `End`, `Insert` or `PrtSc` keys on compact Apple
  keyboards, so those rows use the corresponding `Fn` combinations. In
  terminal apps, `Fn+←/→` maps to
  `Ctrl+A/E` so it works at Bash and Zsh prompts without dotfile changes. That
  mapping is not a universal Home/End replacement inside Vim, less or tmux.
* Moving a window to another workspace has no macOS shortcut at all. It needs a
  tool such as yabai.
* `[1]+D` (EOF) is deliberately not mapped: it is one typo away from closing
  your terminal. EOF stays on `[2]+D` or `[5]+D`. Add `setopt IGNORE_EOF` to
  `~/.zshrc` if you want it on `[1]` with a guard.
* macOS shortcut settings are not version-controlled, and one "Restore Defaults"
  click wipes them.

## Files

| File | Purpose |
|---|---|
| `generate-karabiner.sh` | source of truth: the tables that build the rules |
| `karabiner.json` | generated output |
| `install-karabiner-config.sh` | list profiles, verify, merge |
| `manage-appkit-keybindings.py` | safely install/remove native editing bindings |
| `verify-macos-setup.sh` | 24 read-only checks |
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
This repo trades those rules for one positional remapping plus a few exceptions.

Public domain, as upstream was. See `LICENSE.txt`.
