#!/bin/bash

# On github:
# curl -LsO https://raw.githubusercontent.com/ispanos/YARBS/master/pre-yarbs.sh
# bash pre-yarbs.sh
pacman -Syy
pacman -S --needed --noconfirm dialog termite-terminfo
timedatectl set-ntp true



drive_list_vert=$(/usr/bin/ls -1 /dev | grep "sd.$" && /usr/bin/ls -1 /dev | grep "nvme.*$" | grep -v "p.$")

list_hard_drives(){
	# All mounted partitions in one line, numbered, separated by a space to make the menu list for dialog
	for i in $drive_list_vert ; do
		local -i n+=1
		printf " $n $i"
	done
}

hard_drive_num=$(dialog --title "Select your Hard-drive" --menu "$(lsblk)" 0 0 0 $(list_hard_drives) 3>&1 1>&2 2>&3 3>&1)

HARD_DRIVE="/dev/"$( echo $drive_list_vert | tr " " "\n" | sed -n ${hard_drive_num}p)

ESP_path="/boot"
clear

umount ${HARD_DRIVE}* 2>/dev/null
wipefs -a ${HARD_DRIVE}*

cat <<EOF | fdisk $HARD_DRIVE
g
n


+260M
t
1
n



t

24
w
EOF

if [[ $HARD_DRIVE == *"nvme"* ]]; then
	HARD_DRIVE="${HARD_DRIVE}p"
fi

yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2

mount ${HARD_DRIVE}2 /mnt

mkdir -p /mnt${ESP_path}
mount ${HARD_DRIVE}1 /mnt${ESP_path}

##cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
##curl -L "MIRRORS" > /etc/pacman.d/mirrorlist

pacstrap /mnt base base-devel git termite-terminfo linux-headers

# Capture Warnings?
genfstab -U /mnt >> /mnt/etc/fstab

koulis="https://gist.githubusercontent.com/ispanos/b7460aca88cadb808501dfadb19c342f/raw/45a0929c229532e2fad06d034bdc64a523f3da4b/qwerty.csv"


# option -m MULTILIB
# option -e [gnome,i3,swat]		Sets environment. Only one at a time.
# option -d <link> 		        Sets dotfilesrepo
# option -p <link>				Sets $arglist, for addtitional list of packages.

curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/yarbs.sh && \
arch-chroot /mnt bash yarbs.sh && \
rm /mnt/yarbs.sh || \
printf "\\n\\n\\n\\n\\n\\n\\n\\nsomething went wrong."

dialog --defaultno --yesno "Reboot computer?"  5 30 && reboot
