#!/bin/bash

PARTITION="$2"
MAPPER_NAME="$3"
MOUNT_POINT="$4"

case "$1" in

  install)
    echo "Installing required packages..."
    sudo apt update
    sudo apt install cryptsetup parted -y
    ;;

  list)
    echo "Listing available partitions..."
    sudo lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
    ;;

  edit)
    if [ -z "$PARTITION" ]; then
      echo "Please specify the disk (e.g., /dev/mmcblk0)"
      exit 1
    fi
    echo "Opening parted for disk editing on $PARTITION..."
    sudo parted "$PARTITION"
    ;;

  mount)
    if [ -z "$PARTITION" ] || [ -z "$MAPPER_NAME" ] || [ -z "$MOUNT_POINT" ]; then
      echo "Usage: $0 mount [partition] [mapper_name] [mount_point]"
      exit 1
    fi
    echo "Mounting encrypted partition $PARTITION..."
    sudo cryptsetup open "$PARTITION" "$MAPPER_NAME"
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"
    echo "Partition mounted at $MOUNT_POINT"
    ;;

  unmount)
    if [ -z "$MAPPER_NAME" ] || [ -z "$MOUNT_POINT" ]; then
      echo "Usage: $0 unmount [mapper_name] [mount_point]"
      exit 1
    fi
    echo "Unmounting encrypted partition..."
    sudo umount "$MOUNT_POINT"
    sudo cryptsetup close "$MAPPER_NAME"
    echo "Partition unmounted."
    ;;

  *)
    echo "Usage: $0 {install|list|edit|mount|unmount} [partition] [mapper_name] [mount_point]"
    exit 1
    ;;
esac
