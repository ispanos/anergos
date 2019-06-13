#!/bin/sh

pacman -Syy termite-terminfo pacman-contrib dialog
curl -sL "https://www.archlinux.org/mirrorlist/?country=BE&country=DK&country=FI&country=FR&country=DE&country=GR&country=IT&country=LU&country=MK&country=NO&country=RS&country=SK&country=SI&protocol=https&ip_version=4" > /etc/pacman.d/mirrorlist.backup
sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup
rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup | grep -v "#" > /etc/pacman.d/mirrorlist
pacman -Syy

# Formats the selected partition and mounts it at `/boot`
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

# Verify the boot mode
# ls /sys/firmware/efi/efivars

# Connect to the internet

# Update the system clock
timedatectl set-ntp true


# Partition the disks
# fdisk -l

# Format root partition
mkfs.ext4 /dev/sdX1

chooseesppart
while [ $? -eq 1 ] ; do
	chooseesppart
done

# Formats selected esp partition.
mkfs.fat  -n "ESP" -F 32 $esppart
mkfs.ext4 -L "Arch" /dev/sdX1

mount /dev/sda2 /mnt 
mkdir /mnt/boot && mount $esppart /mnt/boot

pacstrap /mnt base termite-terminfo
#####==> WARNING: Possibly missing firmware for module

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt

cd /tmp && \
curl -sLO https://raw.githubusercontent.com/ispanos/YARBS/master/yarbs.sh && \
sh yarbs.sh

###
###
### NOTES

# run ESP.sh or do that manually. 
# cgdisk /dev/nvme0n1
# New partition
# 512M
# ef00 for /boot

# New partition
# 8e00
# ArchLVM

#Verify

## NOTES FOR YARBS | systemd-boot

# cat > /boot/loader/entries/arch.conf <<EOF
# title   Arch Linux
# linux   /vmlinuz-linux
# initrd  /${cpu}-ucode.img
# initrd  /initramfs-linux.img
# options root=${uuidroot} rw
# EOF
# 
# # If $cpu="nmc", removes the line for ucode.
# [ $cpu = "nmc" ] && cat /boot/loader/entries/arch.conf | grep -v "nmc" > /boot/loader/entries/arch.conf

echo "root:$pass" | chpasswd