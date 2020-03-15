#!/usr/bin/env bash
# License: GNU GPLv3

# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/arch.iso of=/dev/sdx status=progress oflag=sync
export timezone="Europe/Athens"
export lang="en_US.UTF-8"

if [ ! -d "/sys/firmware/efi" ]; then
	echo "Please use UEFI mode." && exit 1
fi

get_drive() {
	# Asks user to select a /dev/sdX or /dev/nvmeXXX device and
	# returns the selected device.
	local drives number
	local -i n=1
	# Sata and NVME drives array
	drives=( $(/usr/bin/ls -1 /dev | grep -P "sd.$|nvme.*$" | grep -v "p.$") )
	lsblk -n >&1 1>&2
	printf "\nPlease select a drive by typing the corresponding number.\n" >&1 1>&2
	for i in "${drives[@]}"; do printf "\t%s - /dev/%s\n" $n $i >&1 1>&2; ((n++)); done
	read -rep "Enter drive's number: " number

	while [[ $(("$number" - 1 )) -ge "${#drives[@]}" ]] || [ -z "$number" ]; do
		echo "Number '$number' is not an available option." >&1 1>&2; unset number
		read -rep "Select a drive by typing the corresponding number: " number
	done

	echo "/dev/${drives[$(("$number" - 1 ))]}"
}

partition_drive() {
	# Uses fdisk to create an "EFI System" partition  (500M),
	# a "Linux root" partition and a "linux home" partition.
	# Obviously it erases all data on the device.
	# Pass the /dev device name as argument. 
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
	# Used after partitioning the device, it formats and mounts
	# the 3 newly created partitions.
	# Obviously it erases all data on the device.
	# Pass the /dev device name as argument. 
	local HARD_DRIVE=$1

	# NVME drives have a "p" before the partition number.
	[[ $HARD_DRIVE == *"nvme"* ]] && HARD_DRIVE="${HARD_DRIVE}p"

	yes | mkfs.ext4 -L "Arch" ${HARD_DRIVE}2
	mount "${HARD_DRIVE}2" /mnt

	mkdir /mnt/boot /mnt/home
	yes | mkfs.fat  -n "ESP" -F 32 ${HARD_DRIVE}1
	mount "${HARD_DRIVE}1" /mnt/boot
	yes | mkfs.ext4 -L "Home" ${HARD_DRIVE}3
	mount "${HARD_DRIVE}3" /mnt/home
}

format_and_mount_partitions(){
	if blkid -o list | grep -q "/mnt \|/mnt/boot" ;then
		cat <<-EOF
			Looks like you have mounted the required partitions [/mnt,/mnt/boot].
			This script is meant for a clean Archlinux installation, so the new /
			partition should be formated. If you are dual-booting, make sure you 
			don't erase the EFI partition of your other OS.

			Please make sure /mnt is formated before you continue:
			$(du -hx -d 0 /mnt)

			NO changes have been made so far.
		EOF

		read -rep "Press ENTER to continue or type 'exit' to exit: " warn
		while [ "$warn" ]; do
			[[ "$warn" == "exit" ]] && exit 1
			read -rep "Press ENTER to continue or type 'exit' to exit: " warn
		done

	else
		cat <<-EOF

			Looks like you haven't mounted the required partitions [/mnt,/mnt/boot].
			If you have mounted one or more partitions from the drive you plan to
			install Archlinux on, please exit ths script and make sure /mnt and /boot
			are both mounted properly. Otherwise this script may fail.

			This script provides a quick way to format and partition a drive in to 3
			partitions [/,/boot,/home]. The newly created partitions are going to be
			formated and ALL DATA ON THE DRIVE WILL BE LOST.
			If you continue, you will be prompted to select a drive. 

			I recommend this only for testing on a VM. 

			To continue type either 'Y' or 'y'. Any other input will terminate
			the script. NO changes have been made so far.
		EOF
		read -rep "[y/N]: " format

		[[ $format =~ ^[Yy]$ ]] || exit 1
		# Select main drive
		local HARD_DRIVE
		HARD_DRIVE=$(get_drive) || exit 1

		partition_drive "$HARD_DRIVE"
		format_mount_parts "$HARD_DRIVE"
	fi
}


get_username() {
	# Ask for the name of the main user.
	local get_name
	read -rep $'Please enter a name for a user account: \n' get_name

	while ! echo "$get_name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		read -rep $'Invalid name. Try again: \n' get_name
	done
    echo "$get_name"
}


get_pass() {
	# Pass the name of the user as an argument.
    local cr le_usr get_pwd_pass check_4_pass
	cr=$(echo $'\n.'); cr=${cr%.}
	le_usr="$1"
    read -rsep $"Enter a password for $le_usr: $cr" get_pwd_pass
    read -rsep $"Retype ${le_usr}'s password: $cr" check_4_pass

    while ! [ "$get_pwd_pass" = "$check_4_pass" ]; do unset check_4_pass
        read -rsep \
		$"Passwords didn't match. Retype ${le_usr}'s password: " get_pwd_pass
        read -rsep $"Retype ${le_usr}'s password: " check_4_pass
    done

    echo "$get_pwd_pass"
}


systemd_boot() {
	# Installs and configures systemd-boot.
	bootctl --path=/boot install

	cat > /boot/loader/loader.conf <<-EOF
		default  ArchLinux
		console-mode max
		editor   no
	EOF

	#  UUID of the partition mounted as "/"
	local root_id="$(lsblk --list -fs -o MOUNTPOINT,UUID | \
					grep "^/ " | awk '{print $2}')"

	local kernel_parms="rw quiet" # Default kernel parameters.

	# I need this to avoid random crashes on my main pc (AMD R5 1600)
	# https://forum.manjaro.org/t/amd-ryzen-problems-and-fixes/55533
	lscpu | grep -q "AMD Ryzen" && kernel_parms="$kernel_parms idle=nowait"

	# Bootloader entry using `linux` kernel:
	cat > /boot/loader/entries/ArchLinux.conf <<-EOF
		title   Arch Linux
		linux   /vmlinuz-linux
		initrd  /${cpu}-ucode.img
		initrd  /initramfs-linux.img
		options root=UUID=${root_id} $kernel_parms
	EOF

	# A hook to update systemd-boot after systemd package updates.
	cat > /etc/pacman.d/hooks/bootctl-update.hook <<-EOF
		[Trigger]
		Type = Package
		Operation = Upgrade
		Target = systemd

		[Action]
		Description = Updating systemd-boot
		When = PostTransaction
		Exec = /usr/bin/bootctl update
	EOF
}


grub_mbr() {
	# grub option is not tested much and only works on MBR partition tables
	# Avoid using it as is.
	local grub_path
	pacman --noconfirm --needed -S grub
	grub_path=$(
		lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
	grub-install --target=i386-pc $grub_path
	grub-mkconfig -o /boot/grub/grub.cfg
}


core_arch_install() {
	systemctl enable --now systemd-timesyncd.service
	ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
	hwclock --systohc
	sed -i "s/#${lang} UTF-8/${lang} UTF-8/g" /etc/locale.gen
	locale-gen > /dev/null 2>&1
	echo 'LANG="'$lang'"' > /etc/locale.conf

	echo "$hostname" > /etc/hostname
	cat > /etc/hosts <<-EOF
		#<ip-address>  <hostname.domain.org>    <hostname>
		127.0.0.1      localhost.localdomain    localhost
		::1            localhost.localdomain    localhost
		127.0.1.1      ${hostname}.localdomain  $hostname
	EOF

	# Enable [multilib] repo, if multi_lib_bool == true
	if [ "$multi_lib_bool" = true  ]; then
		sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
		pacman -Sy && pacman -Fy
	fi

	# Install cpu microcode.
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") local cpu="intel";;
		"AuthenticAMD") local cpu="amd" ;;
	esac

	pacman --noconfirm --needed -S "${cpu}-ucode"

	# This folder is needed for pacman hooks
	mkdir -p /etc/pacman.d/hooks

	# Install bootloader
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot
		pacman --noconfirm --needed -S efibootmgr
	else
		grub_mbr
	fi

	# Set root password
	if [ "$root_password" ]; then
		printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1
	else
		echo "ROOT PASSWORD IS NOT SET!!!! Disable root login or set one later."
		read -rep "Please press ENTER to continue."
		# find a way to fix this.
		#passwd -l root
	fi

	useradd -m -g wheel -G power -s /bin/zsh "$name" # Create user
	echo "$name:$user_password" | chpasswd 			# Set user password.

	echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel

	# Use all cpu cores to compile packages
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf

    printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc

	echo "blacklist pcspkr" >> /etc/modprobe.d/disablebeep.conf

	# Use all cpu cores to compile packages
	sudo sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

	# Creates a swapfile. 2Gigs in size.
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile >/dev/null 2>&1
	swapon /swapfile
	printf "\\n/swapfile none swap defaults 0 0\\n" >> /etc/fstab
	printf "vm.swappiness=10\\nvm.vfs_cache_pressure=50" \
			>> /etc/sysctl.d/99-sysctl.conf

	systemctl enable NetworkManager
}

# User inputs.
hostname=$(read -rep $'Enter computer\'s hostname: \n' var; echo $var)
name=$(get_username)
user_password="$(get_pass $name)"

# If root_passwdrd is not set, root login should be disabled.
# root_password="$(get_pass root)"

# multilib
read -rep "
Would you like to enable multilib (for gaming)? 
(defaults to no)[y/N]: " multi_lib_bool_ans



# This is where the action starts.
timedatectl set-ntp true

# If you have mounted a partition at /mnt, it doens't format it.
format_and_mount_partitions


if [[ $multi_lib_bool_ans =~ ^[Yy]$ ]]; then
	export multi_lib_bool=true
fi

export hostname name user_password root_password

pacstrap /mnt base base-devel git linux linux-headers linux-firmware \
			  man-db man-pages usbutils nano pacman-contrib expac arch-audit \
			  networkmanager openssh flatpak zsh zsh-syntax-highlighting

genfstab -U /mnt > /mnt/etc/fstab
export -f systemd_boot grub_mbr core_arch_install
arch-chroot /mnt bash -c core_arch_install

# TODO
# Add encryption
# Add Grub
# Incorporate snapshots after updates
