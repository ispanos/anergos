#!/usr/bin/env bash
# License: GNU GPLv3

# setfont sun12x22 #HDPI
# dd bs=4M if=path/to/arch.iso of=/dev/sdx status=progress oflag=sync

export multi_lib_bool=true
export timezone="Europe/Athens"
export lang="en_US.UTF-8"

get_drive() {
    # Sata and NVME drives array
    drives=( $(/usr/bin/ls -1 /dev | grep -P "sd.$|nvme.*$" | grep -v "p.$") )

	# 1 sda 2 sdb 3 sdc 4 nvme0n1 .....
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
	# Uses fdisk to create an "EFI System" partition  (500M),
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
	[[ $HARD_DRIVE == *"nvme"* ]] && HARD_DRIVE="${1}p"

	yes | mkfs.ext4 -L "Arch" ${1}2
	mount ${1}2 /mnt

	yes | mkfs.fat  -n "ESP" -F 32 ${1}1
	mkdir /mnt/boot && mount ${1}1 /mnt/boot

	yes | mkfs.ext4 -L "Home" ${1}3
	mkdir /mnt/home && mount ${1}3 /mnt/home
}


## Archlinux installation ##
get_username() {
	# Ask for the name of the main user.
	local get_name
	read -rep $'Please enter a name for a user account: \n' get_name

	while ! echo "$get_name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		read -rep $'Invalid name. Try again: \n' get_name
	done
    echo $get_name
}


get_pass() {
	# Pass the name of the user as an argument.
    local cr=`echo $'\n.'`; cr=${cr%.}
    local le_usr="$1"
	local get_pwd_pass
	local check_4_pass
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
	# Installs and configures systemd-boot. (only for archlinux atm.)
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
	pacman --noconfirm --needed -S grub
	local grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | \
				grep "^/ " | awk '{print $2}')
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

	echo $hostname > /etc/hostname
	cat > /etc/hosts <<-EOF
		#<ip-address>   <hostname.domain.org>    <hostname>
		127.0.0.1       localhost.localdomain    localhost
		::1             localhost.localdomain    localhost
		127.0.1.1       ${hostname}.localdomain  $hostname
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
	if [ -z "$root_password" ]; then
		printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1
	fi

	echo "blacklist pcspkr" >> /etc/modprobe.d/disablebeep.conf

	useradd -m -g wheel -G power -s /bin/bash "$name" # Create user
	echo "$name:$user_password" | chpasswd 			# Set user password.

	pacman --noconfirm --needed -S  man-db man-pages usbutils nano \
		base-devel git pacman-contrib expac arch-audit networkmanager

	systemctl start NetworkManager

	echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel

	# Use all cpu cores to compile packages
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf

	sudo -u "$name" git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
	cd /tmp/yay && sudo -u "$name" makepkg -si --noconfirm

    printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc
}

export hostname=$(read -rep $'Enter computer\'s hostname: \n' var; echo $var)
export name=$(get_username)
export user_password="$(get_pass $name)"

# Select main drive
HARD_DRIVE=$( get_drive )
# Partition drive. 		!!! DELETES ALL DATA !!!
clear; partition_drive $HARD_DRIVE
# Formats the drive. 	!!! DELETES ALL DATA !!!
format_mount_parts $HARD_DRIVE
timedatectl set-ntp true
pacstrap /mnt base linux linux-headers linux-firmware
genfstab -U /mnt > /mnt/etc/fstab
export -f systemd_boot grub_mbr core_arch_install
export hostname
arch-chroot /mnt bash -c core_arch_install
