#!/bin/sh

# This script formats the selected partition and mounts it at `/boot`

chooseesppart() {

	# Outputs the number assigned to selected partition
	declare -i esppartnumber
	esppartnumber=$(dialog 	--title "Please select your ESP partition to be formated and mounted at /boot:" \
							--menu "$(lsblk) " 0 0 0 $(listpartnumb) 3>&1 1>&2 2>&3 3>&1)
	
	# Exit the process if the user selects <cancel> instead of a partition.
	[ $? -eq 1 ] && error "You didn't select any partition. Exiting..."

	# This is the desired partition.
	esppart=$( blkid -o list | awk '{print $1}'| grep "^/" | tr ' ' '\n' | sed -n ${esppartnumber}p)
	
	# Ask user for confirmation.
	dialog --title "Please Confirm" \
	--yesno "Are you sure you want to format partition \"$esppart\" (after final confirmation)?" 0 0
}

chooseesppart
while [ $? -eq 1 ] ; do
	chooseesppart
done

#	Test:
#	echo $esppart

# Formats selected esp partition.
mkfs.fat -F 32 $esppart

# Mounts the selected esp partition to /mnt/boot
mount $esppart /mnt/boot || mkdir /mnt/boot && mount $esppart /mnt/boot
