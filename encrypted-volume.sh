#!/bin/bash

PARTITION="$2"
SIZE="$3"
MAPPER_NAME="$4"
MOUNT_POINT="$5"

case "$1" in

  install)
    echo "Installing required packages..."
    sudo apt update
    sudo apt install cryptsetup parted e2fsprogs -y
    ;;

  list)
    echo "Listing available partitions..."
    sudo lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
    ;;
    
  list-free)
    if [ -z "$PARTITION" ]; then
      echo "Usage: $0 list-free [partition]"
      exit 1
    fi  
    echo "Listing free space..."
    sudo parted $PARTITION print free
    ;;
    
  resize)
    if [ -z "$PARTITION" ]; then
      echo "Usage: $0 resize [partition] [size (optional, e.g., 10G)]"
      exit 1
    fi
    echo "Resizing filesystem for $PARTITION..."
    if [ -z "$SIZE" ]; then
      sudo resize2fs "$PARTITION"
    else
      sudo resize2fs "$PARTITION" "$SIZE"
    fi
    echo "Filesystem resize completed."
    ;;

  edit)
    if [ -z "$PARTITION" ]; then
      echo "Please specify the disk (e.g., /dev/mmcblk0)"
      exit 1
    fi
    echo "Opening parted for disk editing on $PARTITION..."
    sudo parted "$PARTITION"
    ;;

  create)
    if [ -z "$PARTITION" ] || [ -z "$SIZE" ] || [ -z "$MAPPER_NAME" ]; then
      echo "Usage: $0 create [disk] [size, e.g., 250GB] [mapper_name]"
      exit 1
    fi

    echo "Finding free space on $PARTITION for size $SIZE..."
    FREE_RANGE=$(sudo parted -m "$PARTITION" unit GB print free | awk -F: -v size="$SIZE" '
      /free/ {
        start=$2; end=$3;
        gsub("GB", "", start); gsub("GB", "", end);
        if ((end - start) >= size+0) {
          print start " " end;
          exit;
        }
      }')

    if [ -z "$FREE_RANGE" ]; then
      echo "Error: No suitable free space of at least $SIZE found on $PARTITION."
      exit 1
    fi

    START=$(echo "$FREE_RANGE" | cut -d' ' -f1)
    END=$(echo "$FREE_RANGE" | cut -d' ' -f2)

    echo "Creating a new partition from ${START}GB to ${END}GB on $PARTITION..."
    sudo parted -s "$PARTITION" mkpart primary ext4 "${START}GB" "${END}GB"
    sleep 2

    LAST_PART=$(lsblk -ln "$PARTITION" | awk '{print $1}' | tail -n1)
    NEW_PART="/dev/${LAST_PART}"

    for i in {1..5}; do
      if [ -b "$NEW_PART" ]; then
        break
      fi
      echo "Waiting for $NEW_PART to appear..."
      sleep 1
    done

    if [ ! -b "$NEW_PART" ]; then
      echo "Error: New partition $NEW_PART was not found."
      exit 1
    fi

    # Check if LUKS signature already exists
    if sudo cryptsetup isLuks "$NEW_PART"; then
      echo "LUKS signature detected on $NEW_PART. Wiping..."
      sudo dd if=/dev/zero of="$NEW_PART" bs=1M count=16 status=progress
      sync
    fi

    echo "Encrypting $NEW_PART with LUKS..."
    sudo cryptsetup luksFormat "$NEW_PART"

    echo "Opening encrypted partition as $MAPPER_NAME..."
    sudo cryptsetup open "$NEW_PART" "$MAPPER_NAME"

    echo "Formatting /dev/mapper/$MAPPER_NAME as ext4..."
    sudo mkfs.ext4 "/dev/mapper/$MAPPER_NAME"

    echo "Encrypted partition $NEW_PART created and mapped as /dev/mapper/$MAPPER_NAME"
    ;;

  mount)
    PARTITION="$2"
    MAPPER_NAME="$3"
    MOUNT_POINT="$4"
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
    MAPPER_NAME="$2"
    MOUNT_POINT="$3"
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
    echo "Usage: $0 {install|list|list-free|resize|edit|create|mount|unmount} [partition] [mapper_name/size] [mount_point]"
    exit 1
    ;;
esac
