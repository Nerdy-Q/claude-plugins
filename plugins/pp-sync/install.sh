#!/usr/bin/env bash
# install.sh — One-time setup for the pp CLI dispatcher.
#
# What this does:
#   1. Symlinks bin/pp into ~/.local/bin/ (or BIN_DIR if you set it)
#   2. Creates the config dir at ~/.config/nq-pp-sync/
#   3. Prints PATH guidance if ~/.local/bin/ isn't already in PATH
#   4. Tells you to run `pp setup` next
#
# Usage:
#   ./install.sh                    # symlink to ~/.local/bin/pp
#   BIN_DIR=/usr/local/bin ./install.sh   # different bin dir

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SOURCE="$PLUGIN_DIR/bin/pp"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
BIN_TARGET="$BIN_DIR/pp"
CONFIG_DIR="${PP_CONFIG_DIR:-$HOME/.config/nq-pp-sync}"

if [ -t 1 ]; then
    BOLD=$'\033[1m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
else
    BOLD=""; GRN=""; YLW=""; RST=""
fi

[ -f "$BIN_SOURCE" ] || { echo "ERROR: $BIN_SOURCE not found" >&2; exit 1; }

# 1. Ensure pp is executable
chmod +x "$BIN_SOURCE"

# 2. Create bin dir + symlink
mkdir -p "$BIN_DIR"
if [ -L "$BIN_TARGET" ]; then
    # Existing symlink — safe to replace (we own it).
    rm -f "$BIN_TARGET"
elif [ -e "$BIN_TARGET" ]; then
    # A real file (not a symlink) means a different `pp` is installed
    # — back it up rather than silently overwriting.
    backup="$BIN_TARGET.bak.$(date +%Y%m%d-%H%M%S)"
    echo "${YLW}⚠${RST} $BIN_TARGET is a regular file, not a symlink."
    echo "    Backing up to: $backup"
    mv "$BIN_TARGET" "$backup"
fi
ln -s "$BIN_SOURCE" "$BIN_TARGET"
echo "${GRN}✓${RST} Symlinked: $BIN_TARGET -> $BIN_SOURCE"

# 3. Create config dir
mkdir -p "$CONFIG_DIR/projects"
touch "$CONFIG_DIR/aliases"
echo "${GRN}✓${RST} Config dir: $CONFIG_DIR"

# 4. PATH check
if ! echo "$PATH" | tr ':' '\n' | grep -qFx "$BIN_DIR"; then
    echo
    echo "${YLW}⚠${RST} $BIN_DIR is not in your PATH."
    echo "Add this to your shell rc (~/.zshrc, ~/.bashrc):"
    echo
    echo "${BOLD}  export PATH=\"$BIN_DIR:\$PATH\"${RST}"
    echo
    echo "Then reload your shell or run: source ~/.zshrc"
fi

# 5. Verify pp runs
if "$BIN_TARGET" help >/dev/null 2>&1; then
    echo "${GRN}✓${RST} pp is callable"
else
    echo "${YLW}⚠${RST} pp installed but failed to run. Check: $BIN_TARGET help"
fi

# 6. Optional: install shell completions
COMPLETION_DIR="$PLUGIN_DIR/completion"
if [ -d "$COMPLETION_DIR" ]; then
    # bash: prefer ~/.bash_completion.d/, fall back to per-user $XDG_DATA_HOME path
    if [ -d "$HOME/.bash_completion.d" ]; then
        cp "$COMPLETION_DIR/pp.bash" "$HOME/.bash_completion.d/pp" 2>/dev/null \
            && echo "${GRN}✓${RST} bash completion: $HOME/.bash_completion.d/pp"
    else
        echo "${YLW}⚠${RST} bash completion available at: $COMPLETION_DIR/pp.bash"
        echo "    To enable, add to ~/.bashrc:  source $COMPLETION_DIR/pp.bash"
    fi

    # zsh: install into ~/.zsh/completions/ if user has it
    if [ -d "$HOME/.zsh/completions" ]; then
        cp "$COMPLETION_DIR/_pp" "$HOME/.zsh/completions/_pp" 2>/dev/null \
            && echo "${GRN}✓${RST} zsh completion: $HOME/.zsh/completions/_pp"
        echo "    Run:  autoload -Uz compinit && compinit"
    else
        echo "${YLW}⚠${RST} zsh completion available at: $COMPLETION_DIR/_pp"
        echo "    To enable: mkdir -p ~/.zsh/completions && cp $COMPLETION_DIR/_pp ~/.zsh/completions/"
        echo "    Then add to ~/.zshrc:  fpath=(~/.zsh/completions \$fpath); autoload -Uz compinit && compinit"
    fi
fi

echo
echo "${BOLD}Next:${RST}"
echo "  pp setup           # auto-detect Power Pages projects on this machine"
echo "  pp list            # see what's registered"
echo "  pp help            # full command reference"
