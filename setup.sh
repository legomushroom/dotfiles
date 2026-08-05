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
