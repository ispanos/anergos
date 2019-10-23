#!/usr/bin/env bash
# License: GNU GPLv3


raw_repo=https://raw.githubusercontent.com/ispanos/anergos/master

# curl -LsO "https://raw.githubusercontent.com/ispanos/anergos/master/pre_anergos.sh"
# bash pre-anergos.sh
# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/archlinux.iso of=/dev/sdx status=progress oflag=sync

get_drive() {
    # Sata and NVME drives array
    drives=( $(/usr/bin/ls -1 /dev | grep -P "sd.$|nvme.*$" | grep -v "p.$") )

	# "NUM drive" for dialog prompt. Starts from 0 for compatibility with arrays
    local -i n=0
	for i in "${drives[@]}" ; do
		dialog_prompt="$dialog_prompt $n $i"
        ((n++))
	done

    # Prompts user to select one of the available sda or nvme drives.
    local dialogOUT
    dialogOUT=$(dialog --title "Select your Hard-drive" \
            --menu "$(lsblk)" 0 0 0 $dialog_prompt 3>&1 1>&2 2>&3 3>&1 ) || exit

    # Converts dialog output to the actuall name of the selected drive.
    echo "/dev/${drives[$dialogOUT]}"
    }

partition_drive() {
	# Uses fdisk to create an "EFI System" partition  (260M), 
	# a "Linux root" partition and a "linux home" partition.
	cat <<-EOF | fdisk --wipe-partitions always $1
		g
		n
		1

		+500M
		t
		1
		n
		2

		+38G
		t
		2
		24
		n
		3


		t
		3
		28
		w
	EOF
	}

format_mount_parts() {
	[[ $HARD_DRIVE == *"nvme"* ]] && HARD_DRIVE="${HARD_DRIVE}p"

	yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2
	mount ${HARD_DRIVE}2 /mnt

	yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
	mkdir /mnt/boot && mount ${HARD_DRIVE}1 /mnt/boot

	yes | mkfs.ext4 -L "Home" /dev/sda3
	mkdir /mnt/home && mount ${HARD_DRIVE}3 /mnt/home
	}

run_anergos() {
	if [ -r anergos.sh ]; then
		cp anergos.sh /mnt/anergos.sh
	else
		curl -sL "$raw_repo/anergos.sh" > /mnt/anergos.sh
	fi

	echo "anergos.sh copied to /mnt/anergos.sh"

	if [ ! $1 ]; then
		1>&2 echo "No arguments passed. Please read the scripts description."
		exit
	fi

	arch-chroot /mnt bash anergos.sh "$@"
	rm /mnt/anergos.sh
	}

pacman -Sy --needed --noconfirm dialog
timedatectl set-ntp true

HARD_DRIVE=$( get_drive )
partition_drive $HARD_DRIVE
clear
format_mount_parts

pacstrap /mnt base
genfstab -U /mnt >> /mnt/etc/fstab

run_anergos "$@"
dialog --yesno "Reboot computer?"  5 30 && reboot
dialog --yesno "Return to chroot environment?" 6 30 && arch-chroot /mnt
