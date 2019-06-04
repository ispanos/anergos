#!/bin/sh

# This script installs systemd-boot as a boot loader and creates the necessary config files
# during Archlinux installation, so that the system can boot after a restart.
# Also installs cpu microcode if specified by user.

# `/etc/pacman.d/hooks/bootctl-update.hook` file
bootupthook="https://raw.githubusercontent.com/ispanos/YARBS/master/files/bootctl-update.hook"
# `/boot/loader/loader.conf` file
btloaderconf="https://raw.githubusercontent.com/ispanos/YARBS/master/files/loader.conf"

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


# Creates variable `rootuuid`, needed for loader's entry. Only tested non-encrypted partitions.
chooserootpart() {
	local -i rootpartnumber
	local rootpart

	# Outputs the number assigned to selected partition
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

# Temporary solution incase of LUKS/LVM
dialog --title "LVM/LUKS" \
		--yesno "Is your root partition encrypted?" 0 0

# Replace this part with an LUKS/LVM solution.
[ $? -eq 0 ] && dialog --infobox \
"Tough luck. This script cant handle it. You should probalby select <Yes> if 
your "/" partition is encrypted, but feel free to select\ <No> if you are 
willing to risk it. You will need to edit the options of the created enties 
in "/boot/loader/enties"\ to make this work." 6 80 && \
sleep 10 && \
dialog --title "LUKS/LVM" \
		--yesno "Are you sure you want to try?" 0 0 && \
[ $? -eq 1 ] && echo "error 'User exited'"

chooserootpart
while [ $? -eq 1 ] ; do
	chooserootpart
done

#	# For TESTING ONLY
#	cat > ~/tmp <<EOF
#	title   Arch Linux
#	linux   /vmlinuz-linux
#	initrd  /$cpu-ucode.img
#	initrd  /initramfs-linux.img
#	options root=${rootuuid} rw
#	EOF
#	clear

#	echo $rootuuid
#	echo $cpu
#	echo
#	cat ~/tmp


# Installs cpu's microcode if the cpu is either intel or amd.
instmicrocode

# Installs systemd-boot to the eps partition
bootctl --path=/boot install
 
# Creates pacman hook to update systemd-boot after package upgrade.
mkdir -p /etc/pacman.d/hooks
curl $bootupthook > /etc/pacman.d/hooks/bootctl-update.hook
 
# Creates loader.conf. Stored in files/ folder on repo.
curl $btloaderconf > /boot/loader/loader.conf


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

########### To do:
# Add linux-lts entry (for loop for all `/vmlinuz-*` kernels or a sed command just for lts?)
# Need help to add LUKS/LVM support. 