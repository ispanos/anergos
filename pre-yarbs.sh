#!/bin/bash

timedatectl set-ntp true

pacman -Syy termite-terminfo pacman-contrib dialog
curl -sL "https://www.archlinux.org/mirrorlist/?country=BE&country=DK&country=FI&country=FR&country=DE&country=GR&country=IT&country=LU&country=MK&country=NO&country=RS&country=SK&country=SI&protocol=https&ip_version=4" > /etc/pacman.d/mirrorlist.backup
sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup
rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup | grep -v "#" > /etc/pacman.d/mirrorlist
pacman -Syy


pacstrap /mnt base base-devel git termite-terminfo
# Capture Warnings?
genfstab -U /mnt >> /mnt/etc/fstab


curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/tmp/yarbs.sh && \
arch-chroot /mnt bash /mnt/tmp/yarbs.sh || clear && echo "something went wrong."
