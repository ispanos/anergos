#!/bin/sh

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

# Asks user for CPU type and creates $cpu variable, to install the proper microcode later.
getcpu() {

	# Asks user to choose between "inte" abd "amd" cpu, to install microcode. 
	# <Cancel> doen't install any microcode
	local -i answer
	answer=$(dialog --title "Microcode" \
					--menu "Warning: Cancel to skip microcode installation.\\n\\n\
							Choose what cpu microcode to install:" 0 0 0 1 "AMD" 2 "Intel" 3>&1 1>&2 2>&3 3>&1)
	
	# Sets the $cpu variable according to the anwser
	cpu="NoMicroCode"
	[ $answer -eq 1 ] && cpu="amd"
	[ $answer -eq 2 ] && cpu="intel"

	# Asks user to confirm answer.
	[ $cpu = "NoMicroCode" ] && \
	dialog 	--title "Please Confirm" \
			--yesno "Are you sure you don't want to install any microcode?" 0 0 || \
	dialog 	--title "Please Confirm" \
			--yesno "Are you sure you want to install $cpu-ucode? (after final confirmation)" 0 0
}

# Installs microcode if cpu is AMD or Intel.
instmicrocode() {
	( [ $cpu = "amd" ] || [ $cpu = "intel" ]  )  && \
	pacman --noconfirm --needed -S ${cpu}-ucode   >/dev/null 2>&1
}

# All mounted partitions in one line, separated by a space.
partitions=$(blkid -o list | awk '{print $1}'| grep "^/")

# Adds a number infornt of every partition to make the menu list for dialog ( all in one line)
listpartnumb(){
	for i in $partitions ; do
		declare -i n+=1
		printf " $n $i"
	done
}

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

#
chooserootpart() {

	# Outputs the number assigned to selected partition
	declare -i rootpartnumber
	rootpartnumber=$(dialog --title "Please select your root partition (UUID needed for systemd-boot).:" \
							--menu "$(lsblk) " 0 0 0 $(listpartnumb) 3>&1 1>&2 2>&3 3>&1)
	
	# Exit the process if the user selects <cancel> instead of a partition.
	[ $? -eq 1 ] && error "You didn't select any partition. Exiting..."

	# This is the desired partition.
	rootpart=$( blkid -o list | awk '{print $1}'| grep "^/" | tr ' ' '\n' | sed -n ${rootpartnumber}p)

	# This is the UUID=<number>, neeeded for the systemd-boot entry.
	rootuuid=$( blkid $rootpart | tr " " "\n" | grep "^UUID" | tr -d '"' )
	
	# Ask user for confirmation.
	dialog --title "Please Confirm" \
			--yesno "Are you sure this \"$rootpart - $rootuuid\" is your roor partition UUID?" 0 0
}


getcpu
while [ $? -eq 1 ] ; do
	getcpu	
done

chooseesppart
while [ $? -eq 1 ] ; do
	chooseesppart
done

chooserootpart
while [ $? -eq 1 ] ; do
	chooserootpart
done

#	# For TESTING ONLY
#		rm ~/tmp
#	cat > ~/tmp <<EOF
#	title   Arch Linux
#	linux   /vmlinuz-linux
#	initrd  /$cpu-ucode.img
#	initrd  /initramfs-linux.img
#	options root=${rootuuid} rw
#	EOF
#	clear
#	echo $esppart
#	echo $rootpart
#	echo $rootuuid
#	echo $cpu
#	echo
#	cat ~/tmp


# Formats selected esp partition.
mkfs.fat -F 32 $esppart

# Mounts the selected esp partition to /mnt/boot
mount $esppart /mnt/boot || mkdir /mnt/boot && mount $esppart /mnt/boot

# Installs cpu's microcode if the cpu is either intel or amd.
instmicrocode

# Installs systemd-boot to the eps partition
bootctl --path=/boot install
 
# Creates pacman hook to update systemd-boot after package upgrade.
mkdir -p /etc/pacman.d/hooks
curl https://raw.githubusercontent.com/ispanos/YARBS/master/files/bootctl-update.hook \
											> /etc/pacman.d/hooks/bootctl-update.hook
 
# Creates loader.conf. Stored in files/ folder on repo.
curl https://raw.githubusercontent.com/ispanos/YARBS/master/files/loader.conf \
													> /boot/loader/loader.conf


########### To do:
# Add linux-lts entry (for loop?)

# Creates loader entry for root partition, using linux kernel
mkdir -p /boot/loader/entries/
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /${cpu-ucode}.img
initrd  /initramfs-linux.img
options root=${rootuuid} rw
EOF

# If $cpu="NoMicroCode", removes the line for ucode.
[ $cpu = "NoMicroCode" ] && cat /boot/loader/entries/arch.conf | grep -v "ucode.img" \
								> /boot/loader/entries/arch.conf