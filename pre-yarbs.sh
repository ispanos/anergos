#!/bin/bash
# Partitions and formats selected device and then runs yarbs.

# License: GNU GPLv3
# curl -LsO https://raw.githubusercontent.com/ispanos/YARBS/master/pre-yarbs.sh && bash pre-yarbs.sh

## Notes
# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/archlinux.iso of=/dev/sdx status=progress oflag=sync
## setoN

pacman -Syy --needed --noconfirm dialog
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

# Prompts user to select the drive to install the system on.
hard_drive_num=$(dialog --title "Select your Hard-drive" --menu "$(lsblk)" 0 0 0 $(list_hard_drives) 3>&1 1>&2 2>&3 3>&1)

# Converts the number printed by dialog, to the actuall  name of the selected drive.
HARD_DRIVE="/dev/"$( echo $drive_list_vert | tr " " "\n" | sed -n ${hard_drive_num}p)
clear

#	This part is not tested 100%. If you find a better fix please make a PR. 
# 	Especially for NVME drives.
# Unmounts the selected drive and wipes all filesystems, to make repartitioning easier.
umount ${HARD_DRIVE}* 2>/dev/null
wipefs -a ${HARD_DRIVE}*

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

# NVME drives have a different partition naming scheme. 
# This line adds the later "p" at the end of the drive, to make the next step 
# the same for both NVME's and sata drives.
if [[ $HARD_DRIVE == *"nvme"* ]]; then HARD_DRIVE="${HARD_DRIVE}p"; fi

# Format and mount root partition
yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2
mount ${HARD_DRIVE}2 /mnt $root_partition

# Format and mount boot partition.
yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
mkdir -p /mnt/boot
mount ${HARD_DRIVE}1 /mnt/boot

# Install base package, using pacstrap.
if [  -f /usr/share/terminfo/x/xterm-termite ]; then
	# When I'm using ssh, I need termite-terminfo for my terminal.
	# If it's installed on the live system, it means I, the user, need it.
	pacstrap /mnt base termite-terminfo
else
	pacstrap /mnt base
fi

genfstab -U /mnt >> /mnt/etc/fstab

curl -sL "https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh" > /mnt/yarbs.sh 

# TUI and CLI programs.
coreprogs="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/progs.csv"

# GUI programs, mainly for sway and i3. 
common="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/common.csv"

# i3-gaps and some Xorg only packages.
i3="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/i3.csv"

# swaywm and  some wayland packages.
sway="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/sway.csv"

# Steam and nvidia drivers + discord.
gaming="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/gaming-nvidia.csv"

# Very minimal gnone DE.
gnome="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/gnome.csv"

# A friends list of packages.
kk="https://gist.githubusercontent.com/ispanos/b7460aca88cadb808501dfadb19c342f/raw/45a0929c229532e2fad06d034bdc64a523f3da4b/qwerty.csv"


# Default packges lists are [i3,coreprogs,common]. 

# -p 		Sets $prog_files. Add your own link(s) with the list(s) of packages you want to install. -- Overides defaults.
# -m 		Enable multilib.
# -d <link> ' to set your own dotfiles's repo.
arch-chroot /mnt bash yarbs.sh


rm /mnt/yarbs.sh || printf "\\n\\n\\n\\n\\n\\n\\n\\nsomething went wrong."
dialog --yesno "Reboot computer?"  5 30 && reboot
dialog --yesno "Return to chroot environment?" 6 30 && arch-chroot /mnt