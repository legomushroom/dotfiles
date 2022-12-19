#!/bin/bash

# NBD utils

alias cfgdevnbd="code ~/dev-nbd.sh"

export TARGET_CONTAINER_ID="a815b34fc371"

function docker_dir {
    local ROOT_DIR=$(docker info 2>/dev/null | grep -i 'Docker Root Dir:' | sed -r 's/^.*:\s*//g')
    echo "$ROOT_DIR"
}

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

function get_rw_layer_path() {
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

function mount_file() {
    if [ -z "$1" ]; then
        margin "$(roadblock "please provide mount file path")"

        return 1
    fi
    local MOUNT_FILE_PATH="$1"

    if [ -z "$2" ]; then
        margin "$(roadblock "please provide mount point path")"

        return 1
    fi
    local MOUNT_POINT_PATH="$2"

    sudo mount -o loop $MOUNT_FILE_PATH $MOUNT_POINT_PATH

    return $?
}

function unmount_file() {
  if [ -z "$1" ]; then
      margin "$(roadblock "docker container ID")"

      return 1
  fi

  local DOCKER_CONTAINER_ID="$1"
  local MOUNT_POINT_PATH=$(get_rw_layer_path $DOCKER_CONTAINER_ID)

  sudo umount $MOUNT_POINT_PATH

  return $?
}

# Docker

alias d="docker"
alias dc="docker container"

alias ds="docker start -i $TARGET_CONTAINER_ID"
alias dstart="sudo systemctl start docker"
alias dstop="sudo systemctl stop docker"

export DOCKER_MOUNT_POINT_PATH="$(get_rw_layer_path "$TARGET_CONTAINER_ID")"

function dbackup {
  local DEST_PATH="/root/repos/nbd/backup"
  local SRC_PATH="$DOCKER_MOUNT_POINT_PATH"

  rm -rf $DEST_PATH
  mkdir -p $DEST_PATH

  cp -r $SRC_PATH/* $DEST_PATH/
}

alias dcopy="cp -r ./backup/* $DOCKER_MOUNT_POINT_PATH/"
alias dls="ls -la $DOCKER_MOUNT_POINT_PATH/"

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
  local FILE_COUNT="${2:-1}"

  dd if=/dev/zero of=$FILE_PATH bs=$FILE_SIZE count=$FILE_COUNT oflag=dsync
}

# measure IO write latency
function iowlat() {
  local FILE_PATH="${1:-"/tmp/test1.img"}"
  local FILE_SIZE="${2:-1M}"
  local FILE_COUNT="${2:-1000}"

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
