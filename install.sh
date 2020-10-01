sudo apt-get update
sudo apt-get install -y zsh yadm
sudo apt-get install -y gnupg
yadm clone https://github.com/fugufish/dotfiles.git
yadm reset --hard
#CI=1/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
#brew install neovim
#pip3 install neovim
sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
wget https://repo.mongodb.org/apt/debian/dists/stretch/mongodb-org/4.4/main/binary-amd64/mongodb-org-shell_4.4.1_amd64.deb
sudo dpkg -i mongodb-org-shell_4.4.1_amd64.deb      
