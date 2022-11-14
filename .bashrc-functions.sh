#!/bin/bash

# Add new lines before and after string
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

function margin_start() {
  echo -e "\n$1";
}

function margin_end() {
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
  margin_start "$(start "$(green $1) times")";

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
