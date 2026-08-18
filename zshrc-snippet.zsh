# ---------------------------------------------------------------------------
# Linux-style keyboard layout: zsh bindings
#
# Append these lines to ~/.zshrc, then open a new terminal.
#
# WHY THESE SEQUENCES
# -------------------
# Karabiner translates [1]+arrow into Control+arrow inside terminal apps, and
# a terminal transmits Control+arrow as an xterm escape sequence:
#
#     Control+Up     ->  ^[[1;5A        Control+Right  ->  ^[[1;5C
#     Control+Down   ->  ^[[1;5B        Control+Left   ->  ^[[1;5D
#
# zsh sees only those bytes -- it has no idea which physical key produced them.
# That is why nothing here mentions Command, Control or Option: the key
# positions are Karabiner's problem, and this file only deals with what
# actually arrives down the pty. It also means these bindings work unchanged
# over SSH and inside tmux.
#
#   [1] = corner key,  [2] = middle key,  [3] = key next to the spacebar
# ---------------------------------------------------------------------------

# [1]+Up / [1]+Down -- walk history, filtered by what you have already typed.
# Type "git " then press [1]+Up and you cycle only through your git commands.
# On an empty line it behaves like ordinary history.
bindkey "^[[1;5A" history-beginning-search-backward
bindkey "^[[1;5B" history-beginning-search-forward

# [1]+Left / [1]+Right -- move the cursor one word at a time.
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word

# ---------------------------------------------------------------------------
# OPTIONAL: leave the cursor at the end of the recalled line
#
# The plain widgets above put the cursor back where you stopped typing, which
# is rarely what you want. These wrappers move it to the end of the line
# instead. Replace the two history bindings above with these if you prefer.
# ---------------------------------------------------------------------------
# autoload -Uz history-search-end
# zle -N history-beginning-search-backward-end history-search-end
# zle -N history-beginning-search-forward-end  history-search-end
# bindkey "^[[1;5A" history-beginning-search-backward-end
# bindkey "^[[1;5B" history-beginning-search-forward-end

# ---------------------------------------------------------------------------
# OPTIONAL: guard against closing the terminal by accident
#
# [1]+D sends EOF, which ends the shell and closes the window. If you hit it by
# mistake, this makes zsh ask instead. It still deletes a character mid-line.
# ---------------------------------------------------------------------------
# setopt IGNORE_EOF

# ---------------------------------------------------------------------------
# NOT NEEDED
#
# zsh already binds these in its default emacs keymap, so adding them is
# harmless but redundant:
#
#   bindkey "^R"     history-incremental-search-backward
#   bindkey "^[[3~"  delete-char
# ---------------------------------------------------------------------------
