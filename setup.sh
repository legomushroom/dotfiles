#!/bin/sh

DOTFILES_DIR=/tmp/dotfiles
if [ ! -d "$DOTFILES_DIR" ]; then
    git clone https://github.com/legomushroom/dotfiles.git $DOTFILES_DIR
fi

cd $DOTFILES_DIR
git pull

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
