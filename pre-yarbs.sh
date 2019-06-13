#!/bin/bash

#pacman -Syy --needed --noconfirm termite-terminfo dialog

timedatectl set-ntp true

HARD_DRIVE="/dev/sda"
ESP_path="/boot"

umount ${HARD_DRIVE}* 2>/dev/null
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


curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/yarbs.sh && \
arch-chroot /mnt bash /tmp/yarbs.sh && \
rm /mnt/yarbs.sh || \
printf "\\n\\n\\n\\n\\n\\n\\n\\nsomething went wrong." && clear && exit

arch-chroot /mnt bash chroot.sh && rm /mnt/chroot.sh
dialog --defaultno --yesno "Reboot computer?"  5 30 && reboot
dialog --defaultno --yesno "Return to chroot environment?" 6 30 && arch-chroot /mnt
