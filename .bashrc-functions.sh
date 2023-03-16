#!/bin/bash

# TODO: fix locales
# sudo dpkg-reconfigure locales

# Sends a specified message or a spacer(`---`) to the `dmesg` log.
# ## Examples
#
# ```shell
#   kmesg
# ```
# Prints `---`(default spacer) to the `dmesg` log.
# 
# ```shell
#   kmesg xxx
# ```
# Prints `xxx` to the `dmesg` log.
function kmsg() {
    local message="${1:----}"

    echo -e "$message" | sudo tee -a /dev/kmsg > /dev/null
}

# Add new lines before and after string.
#
# ## Examples
# 
# ```shell
#   margin "Hello World!"
# ```
# Prints: `\nHello World!\n`
function margin() {
  echo -e "\n$1\n";
}

function margin-top() {
  echo -e "\n$1";
}

function margin-bottom() {
  echo -e "$1\n";
}

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE="\033[1;34m"
CYAN="\033[1;36m"
NO_COLOR='\033[0m'

function red() {
  echo -e "${RED}$1${NO_COLOR}";
}

function green() {
  echo -e "${GREEN}$1${NO_COLOR}";
}

function yellow() {
  echo -e "${YELLOW}$1${NO_COLOR}";
}

function light-blue() {
  echo -e "${LIGHT_BLUE}$1${NO_COLOR}";
}

function cyan() {
  echo -e "${CYAN}$1${NO_COLOR}";
}

# Icons
OK_ICON=✅
ROADBLOCK_ICON=🚧
PROGRESS_ICON=⌛
BLOWUP_ICON=💣
FAIL_ICON=🛑
BEGIN_ICON=🏁
INFO_ICON=💡

function roadblock() {
  echo -e "$ROADBLOCK_ICON $1";
}

function fail() {
  echo -e "$FAIL_ICON $1";
}

function blowup() {
  echo -e "$BLOWUP_ICON $1";
}

function progress() {
  echo -e "$PROGRESS_ICON $1";
}

function info() {
  echo -e "$INFO_ICON $1";
}

function ok() {
  echo -e "$OK_ICON $1";
}

function success() {
  margin "$(ok 'done')";
}

function failure() {
  local MSG="${1:-failed}"
  margin "$(fail "$MSG")" >&2

  return 1
}

function end-script() {
  if [ $? -eq 0 ]; then
    return success
  else
    return failure
  fi
}

function begin() {
  echo -e "$BEGIN_ICON $1";
}

# Run a command N times.
#
# ## Examples
# 
# Echoes "1" 5 times:
# ```shell
#   runx 5 echo "1"
# ```
#
function runx() {
  for ((i = 0; i < $1; i++)) {
    # echo "\n-- runx: $i\n";
    ${*:2}; 
  }
}

# Same as `runx` but exits if command run yields unsuccessful exit code
#
# ## Examples
# 
# Runs `cargo t -- dns_map::tests::resolve::removes_expired_records_while_adds` command
# 5 times and exits on first unsuccessful result:
# ```shell
#   testx 5 cargo t -- dns_map::tests::resolve::removes_expired_records_while_adds
# ```
function testx() {
  margin-top "$(start "$(green $1) times")";

  for ((i = 1; i <= $1; i++)) {
    margin "$(progress "run $(green $i)")";
    # execute command on current iteration
    ${*:2};
    TESTX_EXIT_CODE=$?;
    # if the current execution was unsuccessful,
    # exit with the same exit code
    if [[ $TESTX_EXIT_CODE != 0 ]]; then
      margin "$(blowup $i)";
      return $TESTX_EXIT_CODE;
    fi
  }

  margin "$(ok "all $(green $1) done")";
}

# Get process PID by process name.
#
# ## Examples
# 
# Gets `gh-net` process PID:
# ```shell
#   proc-pid gh-net
# ```
function proc-pid() {
  if [ -z $1 ]; then
    msg="$(roadblock "please provide process name, e.g. $(yellow 'proc-pid gh-net')")";
    margin "$msg";

    return -1;
  fi

  echo "$(ps -ef | grep $1 | grep -v grep | awk '{print $2}')"
}

# Kill process by name.
#
# ## Examples
# 
# Kills `gh-net` process:
# ```shell
#   kproc gh-net
# ```
function kproc() {
  if [ -z $1 ]; then
    msg="$(roadblock "please provide process name, e.g. $(yellow 'kproc gh-net')")";
    margin "$msg";
    return 1;
  fi

  ps -ef | grep $1 | grep -v grep | awk '{print $2}' | sudo xargs -r kill -9;
}

function msg() {
    local len="${1:-50}"
    dmesg | tail --lines $len
}

function wmsg() {
    local len="${1:-50}"

    watch -n 1 "dmesg | tail --lines $len"
}

# Install GitHub CLI.
function igh() {
  type -p curl >/dev/null || sudo apt install curl -y
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y
}

function imisc() {
  local PREV_LOCATION=$(pwd)

  margin "$(begin "Installing $1.sh..")"

  DOTFILES_DIR=/tmp/dotfiles
  if [ ! -d "$DOTFILES_DIR" ]; then
    margin "$(progress "cloning dotfiles repo..")"

    git clone https://github.com/legomushroom/dotfiles.git $DOTFILES_DIR
  fi

  cd $DOTFILES_DIR
  margin "$(progress "updating dotfiles repo..")"

  git pull

  margin "$(progress "copying $1.sh to home..")"

  cp ./misc/$1.sh ~/
  echo "source ~/$1.sh" >> ~/.bashrc-utils
  
  cd $PREV_LOCATION

  success
}

# Get current timestamp.
function timestamp() {
  echo "$(date +"%s")"
}

# Watch a command every N seconds (N equal to 1 by default).
function ww {
  if [ -z $1 ]; then
    msg="$(roadblock "please provide command to watch on, e.g. $(yellow 'ww "ls /etc"')")";
    margin "$msg";
    return 1;
  fi

  local INTERVAL="${2:-1}"

  watch -n $INTERVAL "$1"
}

# Asserts if a `left` value is equal to a `right` value.
#
# ## Examples
#
# ```shell
# $ assert-eq 'foo' 'foo' // OK
# $ assert-eq 'bar' 'foo' // Error
# $ assert-eq 'bar' 'foo' 'must be equal' // Error with a custom message
# ```
function assert-eq() {
  if [ -z $1 ]; then
    local msg="$(roadblock "please provide a 'left' value to assert")";
    margin "$msg";
    return 1;
  fi

  if [ -z $2 ]; then
    local msg="$(roadblock "please provide a 'right' value to assert")";
    margin "$msg";
    return 1;
  fi

  if [ "$1" != "$2" ]; then
    local ASSERT_MSG="${3:-assertion failed}"
    local NOT_EQUAL_MSG="$(yellow $1) != $(yellow $2)"
    local msg="$(roadblock "$ASSERT_MSG ($NOT_EQUAL_MSG)")";

    margin "$msg";
    return 1;
  fi
}

# Get a parent of a provided filesystem path.
#
# ## Examples
#
# ```shell
# $ result=$(parent-of '/parent/child')
# $ assert-eq $result '/parent'
# ```
function parent-of() {
    if [ -z $1 ]; then
        local msg="$(roadblock "please provide a path")";
        margin "$msg";
        return 1;
    fi
    
    local PARENT_FOLDER="$(dirname $1)"
    
    echo $PARENT_FOLDER
}

# Ensure folder exists.
#
# ## Examples
#
# ```shell
# $ ensure-folder '/parent/child' # creates a folder if it doesn't exist
# ```
function ensure-folder() {
  local FOLDER_LOCATION=$1

  if [ -z "$FOLDER_LOCATION" ]; then
    local msg="$(roadblock "Please specify a folder location.\n\n   Usage: $(yellow 'ensure-folder') $(red '<folder-path>')")"
    margin "$msg"

    return 1
  fi
  
  if [ -d "$FOLDER_LOCATION" ]; then
    # the folder already exists, noop
    return 0
  fi

  # otherwise create the folder
  mkdir -p $FOLDER_LOCATION
}

# Ensure folder exists and is empty.
#
# ## Examples
#
# ```shell
# $ ensure-clean-folder '/parent/child'
# # -> creates a folder if it doesn't exist, otherwise removes it and creates a new one to ensure it's empty
# ```
function ensure-clean-folder() {
  local FOLDER_LOCATION=$1
  
  if [ -z "$FOLDER_LOCATION" ]; then
    local msg="$(roadblock "Please specify a folder location.\n\n   Usage: $(yellow 'ensure-clean-folder') $(red '<folder-path>')")"
    margin "$msg"

    return 1
  fi

  # ensure the folder exists
  ensure-folder $FOLDER_LOCATION
  # ensure the folder is empty
  rm -rf $FOLDER_LOCATION/*
}
