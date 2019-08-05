#!/bin/bash
# License: GNU GPLv3

raw_repo=https://raw.githubusercontent.com/ispanos/anergos/master
# curl -LsO "$raw_repo/anergos.d/pre-anergos.sh" && bash pre-anergos.sh
# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/archlinux.iso of=/dev/sdx status=progress oflag=sync

pacman -Sy --needed --noconfirm dialog
timedatectl set-ntp true

# Converts the number printed by dialog, to the actuall  name of the selected drive.
HARD_DRIVE=/dev/sda


yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}1
mount ${HARD_DRIVE}1 /mnt 

{ [  -f /usr/share/terminfo/x/xterm-termite ] && pacstrap /mnt base termite-terminfo; } || pacstrap /mnt base
genfstab -U /mnt >> /mnt/etc/fstab

{ [ -r anergos.sh ] && cp anergos.sh /mnt/anergos.sh; } || curl -sL "$raw_repo/anergos.sh" > /mnt/anergos.sh

arch-chroot /mnt bash anergos.sh progs i3 common
rm /mnt/anergos.sh

dialog --yesno "Reboot computer?"  5 30 && reboot
dialog --yesno "Return to chroot environment?" 6 30 && arch-chroot /mnt
