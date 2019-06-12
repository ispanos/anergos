#!/bin/bash

timedatectl set-ntp true



pacman -Syy --needed --noconfirm termite-terminfo dialog

cat > /etc/pacman.d/mirrorlist <<'EOF'
##
## Arch Linux repository mirrorlist
## Generated on 2019-06-12
##                Athens

Server = https://foss.aueb.gr/mirrors/linux/archlinux/$repo/os/$arch
Server = https://appuals.com/archlinux/$repo/os/$arch
Server = https://mirror.ubrco.de/archlinux/$repo/os/$arch
Server = https://mirror.wormhole.eu/archlinux/$repo/os/$arch
Server = https://mirror.orbit-os.com/archlinux/$repo/os/$arch
Server = https://mirror.bethselamin.de/$repo/os/$arch
Server = https://mirror.23media.com/archlinux/$repo/os/$arch
Server = https://mirror.metalgamer.eu/archlinux/$repo/os/$arch
Server = https://mirror.f4st.host/archlinux/$repo/os/$arch
Server = https://arch.jensgutermuth.de/$repo/os/$arch
EOF

pacman -Syy


pacstrap /mnt base termite-terminfo
# Capture Warnings?
genfstab -U /mnt >> /mnt/etc/fstab


curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/tmp/yarbs.sh && \
arch-chroot /mnt bash /tmp/yarbs.sh || clear && echo "something went wrong."
