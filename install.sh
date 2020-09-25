sudo apt-get update
sudo apt-get install docker-compose zsh yadm
yadm clone https://github.com/fugufish/dotfiles.git
yadm reset --hard
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
brew install neovim
pip3 install neovim
