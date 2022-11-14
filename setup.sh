#!/bin/sh

DOTFILES_DIR=/tmp/dotfiles
if [ ! -d "$DOTFILES_DIR" ]; then
    git clone https://github.com/legomushroom/dotfiles.git $DOTFILES_DIR
fi

cd $DOTFILES_DIR
git pull

find ./ -iname ".bashrc*" -exec cp {} ~/ \;
