#!/bin/bash

# USBIP
function iusb() {
    set -e

    margin begin "Installing gh-usb extension.."

    cargo make -p production gh-usb-install

    success
}

function list() {
    set -e

    local SERVER_ADDRESS="${1:-'0.0.0.0'}"

    sudo usbip list -r $SERVER_ADDRESS
}

function attach() {
    set -e

    local SERVER_ADDRESS="${2:-'0.0.0.0'}"

    margin begin "Attaching to USBIP server \"$SERVER_ADDRESS\".."

    sudo usbip attach -r $SERVER_ADDRESS -b $1

    success
}

function port() {
    set -e

    local SERVER_ADDRESS="${1:-'0.0.0.0'}"

    sudo usbip port -r $SERVER_ADDRESS
}

alias lusb="ps -ef | grep 'gh-usb' | grep -v grep"
alias kusb="ps -ef | grep 'gh-usb' | grep -v grep | awk '{print $2}' | sudo xargs -r kill -9"

alias upio="pio run -t upload"
alias oocd="openocd -f interface/stlink-v2-1.cfg -f target/stm32f3x.cfg"
