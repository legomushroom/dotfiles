#!/bin/bash

# NBD utils

alias cfgdevnbd="code ~/dev-nbd.sh"

function get-mount-id() {
    if [ -z "$1" ]; then
        margin "$(roadblock "please provide container ID")"

        return
    fi

    local CONTAINER_ID="$1"
    local DEFAULT_STORAGE_DRIVER="$(docker info --format '{{.Driver}}')"
    local STORAGE_DRIVER="${2:-$DEFAULT_STORAGE_DRIVER}"

    local MOUNT_ID="$(cat /var/lib/docker/image/$STORAGE_DRIVER/layerdb/mounts/$CONTAINER_ID*/mount-id)"

    if [ -z $MOUNT_ID ]; then
        margin "$(fail "no mount ID found for container: $(yellow $CONTAINER_ID)")"

        exit 77
    fi

    echo $MOUNT_ID
}

function get-rw-layer-path() {
    if [ -z "$1" ]; then
        margin "$(roadblock "please provide container ID")"

        return
    fi

    local DOCKER_DIR="$(docker_dir)"
    local MOUNT_ID="$(get-mount-id "$1")"

    local DEFAULT_STORAGE_DRIVER="$(docker info --format '{{.Driver}}')"
    local STORAGE_DRIVER="${2:-$DEFAULT_STORAGE_DRIVER}"

    echo "$DOCKER_DIR/$STORAGE_DRIVER/$MOUNT_ID"
}

function create-mount-file() {
    if [ -z "$1" ]; then
        margin "$(roadblock "please provide mount name")"

        return
    fi

    local MOUNT_FILE_NAME="$1"
    local MOUNT_FILE_SIZE="${2:-"1G"}"
    local FILE_SYSTEM="${3:-"ext4"}"

    local MOUNT_FILE_PATH="$(realpath $MOUNT_FILE_NAME)"

    rm -rf $MOUNT_FILE_PATH
    truncate --size $MOUNT_FILE_SIZE $MOUNT_FILE_PATH

    local MKFS_OUTPUT="$(mkfs -t $FILE_SYSTEM $MOUNT_FILE_PATH 2>&1)"

    if [ $? -ne 0 ]; then
        # echo -e "failed to create file system on the mount file $MOUNT_FILE_PATH: \n$MKFS_OUTPUT" >&2
        local FAIL_MESSAGE="failed to create file system on the mount file $(yellow $MOUNT_FILE_PATH)\": \n\n$MKFS_OUTPUT"
        margin "$(fail "$FAIL_MESSAGE")"

        return $?
    fi

    echo $MOUNT_FILE_PATH
}

# Docker

alias d="docker"
alias dc="docker container"

alias dstart="sudo systemctl start docker"
alias dstop="sudo systemctl stop docker"

function drand() {
    if [ -z "$1" ]; then
      margin "$(roadblock "please provide file path")"

      return 1
  fi

  local FILE_PATH="$1"

  dd if=/dev/random of=$FILE_PATH bs=4096 count=50
}

function dzero() {
    if [ -z "$1" ]; then
      margin "$(roadblock "please provide file path")"

      return 1
  fi

  local FILE_PATH="$1"

  dd if=/dev/zero of=$FILE_PATH bs=4096 count=50
}

# measure IO write throughput
function iowthru() {
  local FILE_PATH="${1:-"/tmp/test1.img"}"
  local FILE_SIZE="${2:-1G}"
  local FILE_COUNT="${3:-1}"

  dd if=/dev/zero of=$FILE_PATH bs=$FILE_SIZE count=$FILE_COUNT oflag=dsync
}

# measure IO write latency
function iowlat() {
  local FILE_PATH="${1:-"/tmp/test1.img"}"
  local FILE_SIZE="${2:-1M}"
  local FILE_COUNT="${23:-1000}"

  dd if=/dev/zero of=$FILE_PATH bs=$FILE_SIZE count=$FILE_COUNT oflag=dsync
}

# measure IO read/write with `fio`
alias iofio="fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=4G --readwrite=randrw --rwmixread=75"

# measure disk IO with hdparm
function iohd() {
    if [ -z "$1" ]; then
        return failure
    fi

    local DEVICE_NAME="$1"

    sudo hdparm -Tt /dev/$DEVICE_NAME
}

alias dlogs="journalctl -fu docker.service"
