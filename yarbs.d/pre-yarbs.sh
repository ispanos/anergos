#!/bin/bash
# License: GNU GPLv3

raw_repo=https://raw.githubusercontent.com/ispanos/YARBS/master
# curl -LsO "$raw_repo/yarbs.d/pre-yarbs.sh" && bash pre-yarbs.sh
# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/archlinux.iso of=/dev/sdx status=progress oflag=sync

pacman -Sy --needed --noconfirm dialog
timedatectl set-ntp true

# Vertical list of all sata and NVME drives.
drive_list_vert=$(/usr/bin/ls -1 /dev | grep -P "sd.$|nvme.*$" | grep -v "p.$")

list_hard_drives(){
	# Sata and NVME drives listed in one line, with a number infront of them.
	# This creates the list for the dialog prompt.
	for i in $drive_list_vert ; do
		local -i n+=1
		printf " $n $i"
	done
}

hard_drive_num=$(dialog --title "Select your Hard-drive" --menu "$(lsblk)" 0 0 0 $(list_hard_drives) 3>&1 1>&2 2>&3 3>&1)
# Converts the number printed by dialog, to the actuall  name of the selected drive.
HARD_DRIVE="/dev/"$( echo $drive_list_vert | tr " " "\n" | sed -n ${hard_drive_num}p)
clear

# This part is not tested 100%. If you find a better fix please make a PR. Especially for NVME drives.
# Unmounts the selected drive and wipes all filesystems, to make repartitioning easier.
wipefs -a ${HARD_DRIVE}*
sleep 2

# Uses fdisk to create an "EFI System" partition  (260M) and a "Linux root" partition 
# that takes up the rest of the drive's space.
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

sleep 2

[[ $HARD_DRIVE == *"nvme"* ]] && HARD_DRIVE="${HARD_DRIVE}p"

yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2
mount ${HARD_DRIVE}2 /mnt $root_partition

yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
mkdir -p /mnt/boot && mount ${HARD_DRIVE}1 /mnt/boot

{ [  -f /usr/share/terminfo/x/xterm-termite ] && pacstrap /mnt base termite-terminfo; } || pacstrap /mnt base
genfstab -U /mnt >> /mnt/etc/fstab

{ [ -r yarbs.sh ] && cp yarbs.sh /mnt/yarbs.sh; } || curl -sL "$raw_repo/yarbs.sh" > /mnt/yarbs.sh

arch-chroot /mnt bash yarbs.sh progs i3 common
rm yarbs.sh

dialog --yesno "Reboot computer?"  5 30 && reboot
dialog --yesno "Return to chroot environment?" 6 30 && arch-chroot /mnt