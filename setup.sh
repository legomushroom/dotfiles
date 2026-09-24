#!/bin/sh

# Stop on the first failure: a fetch that fails and then installs whatever the
# last run left behind is worse than not running at all.
set -e

# Piped into sh there is nobody to answer a credential prompt, so an
# unreachable repo should fail rather than hang waiting for a username.
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

REPO_URL=https://github.com/legomushroom/dotfiles.git
DOTFILES_DIR=${DOTFILES_DIR:-/tmp/dotfiles}

# A leftover checkout can be stale, dirty, on another branch, or not even this
# repo, and `git pull` would merge or fail instead of fetching. Reuse it only
# when it really is this repo, and then take origin's state verbatim rather
# than merging into whatever is sitting there. Anything else is re-cloned.
if [ -d "$DOTFILES_DIR/.git" ] &&
    [ "$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null)" = "$REPO_URL" ]; then
    git -C "$DOTFILES_DIR" fetch --quiet origin
    default_branch=$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    git -C "$DOTFILES_DIR" reset --quiet --hard "$default_branch"
    git -C "$DOTFILES_DIR" clean -qfd
else
    rm -rf "$DOTFILES_DIR"
    git clone --quiet "$REPO_URL" "$DOTFILES_DIR"
fi

cd "$DOTFILES_DIR"

find ./ -iname ".bashrc*" -exec cp {} ~/ \;

# Install Copilot CLI custom instructions so they apply in every Codespace.
mkdir -p ~/.copilot/instructions
cp copilot/instructions/*.instructions.md ~/.copilot/instructions/

# Agent skills. Each skill is a folder whose name must match the `name` in its
# SKILL.md, so the whole folder is replaced rather than merged into.
if [ -d ./copilot/skills ]; then
    mkdir -p ~/.copilot/skills
    for skill in ./copilot/skills/*/; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        rm -rf ~/.copilot/skills/"$name"
        cp -R "$skill" ~/.copilot/skills/"$name"
    done
    chmod +x ~/.copilot/skills/*/scripts/*.sh 2>/dev/null || true
fi
