rm -rf ~/.oh-my-bash

function install-with-curl() {
    echo "Installing using 'curl'.."

    curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh | bash

    return $?
}

function install-with-wget() {
    echo "Installing using 'wget'.."

    wget https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh -O - | bash

    return $?
}

function install-ohmybash() {
    local CURL_LOCATION=$(command -v curl 2> /dev/null 2>&1 || echo "")
    if [ ! -z $CURL_LOCATION ]; then

        return install-with-curl
    fi

    local WGET_LOCATION=$(command -v wget 2> /dev/null 2>&1 || echo "")
    if [ ! -z $WGET_LOCATION ]; then

        return install-with-wget
    fi

    echo "No 'curl' or 'wget' found, installing 'curl'.."

    apt update && apt install -y curl

    return install-with-curl
}

set -e

# download and install oh-my-bash
install-ohmybash

# import the dotfiles '.bashrc-utils' by default
echo -e '\nsource ~/.bashrc-utils' >> ~/.bashrc
# trigger initial oh-my-bash setup
source ~/.bashrc

set +e
