sudo apt-get update
sudo apt-get install docker-compose zsh nvim python3 yadm
curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh
yadm clone origin https://github.com/fugufish/dotfiles.git
sudo chsh codespaces /usr/bin/zsh
