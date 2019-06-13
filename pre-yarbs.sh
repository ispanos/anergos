#!/bin/bash

#pacman -Syy --needed --noconfirm termite-terminfo dialog

timedatectl set-ntp true

HARD_DRIVE="/dev/sda"
ESP_path="/boot"

wipefs -a ${HARD_DRIVE}*

cat <<EOF | fdisk $HARD_DRIVE
g
n

+512M
t
1
n


t
24
w
EOF

yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2

mount ${HARD_DRIVE}2 /mnt

mkdir -p /mnt${ESP_path}
mount ${HARD_DRIVE}1 /mnt${ESP_path}

##cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
##curl -L "MIRRORS" > /etc/pacman.d/mirrorlist

pacstrap /mnt base base-devel git termite-terminfo
# Capture Warnings?
genfstab -U /mnt >> /mnt/etc/fstab


curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/tmp/yarbs.sh && \
arch-chroot /mnt bash /tmp/yarbs.sh || printf "\\n\\n\\n\\n\\n\\n\\n\\nsomething went wrong."
