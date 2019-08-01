#!/bin/bash

function set_locale_time() {
	dialog --infobox "Locale and time-sync..." 0 0
	serviceinit systemd-timesyncd.service
	ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
	hwclock --systohc
	sed -i "s/#${lang} UTF-8/${lang} UTF-8/g" /etc/locale.gen
	locale-gen > /dev/null 2>&1
	echo 'LANG="'$lang'"' > /etc/locale.conf
}

######   For LVM/LUKS modify /etc/mkinitcpio.conf   ######
######   sed for HOOKS="...keyboard encrypt lvm2"   ######
######   umkinitcpio -p linux && linux-lts entry?   ######

function get_microcode() {
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
		*)				cpu="no" 	;;
	esac

	if [ $cpu != "no" ]; then
		dialog --infobox "Installing ${cpu} microcode." 3 31
		pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
	fi
}

function systemd_boot() {
	# Installs systemd-boot to the eps partition
	dialog --infobox "Setting-up systemd-boot" 0 0
	bootctl --path=/boot install

	# Creates pacman hook to update systemd-boot after package upgrade.
	mkdir -p /etc/pacman.d/hooks
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

	# Creates loader.conf. Stored in files/ folder on repo.
	cat > /boot/loader/loader.conf <<-EOF
		default  arch
		console-mode max
		editor   no
	EOF

	# sets uuidroot as the UUID of the partition mounted at "/".
	uuidroot="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"

	# Creates loader entry for root partition, using the "linux" kernel
						echo "title   Arch Linux"           >  /boot/loader/entries/arch.conf
						echo "linux   /vmlinuz-linux"       >> /boot/loader/entries/arch.conf
	[ $cpu = "no" ] || 	echo "initrd  /${cpu}-ucode.img"    >> /boot/loader/entries/arch.conf
						echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
						echo "options root=${uuidroot} rw quiet"  >> /boot/loader/entries/arch.conf
}

function grub_mbr() {
		dialog --infobox "Setting-up Grub. -WARNING- ONLY MBR partition table." 0 0
		pacman --noconfirm --needed -S grub >/dev/null 2>&1
		grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
		grub-install --target=i386-pc $grub_path >/dev/null 2>&1
		grub-mkconfig -o /boot/grub/grub.cfg
}

function inst_bootloader() {
	get_microcode
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot
		pacman --needed -noconfirm -S efibootmgr > /dev/null 2>&1
		dialog --infobox "Installing efibootmgr, a tool to modify UEFI Firmware Boot Manager Variables." 4 50
	else
		grub_mbr
	fi
}

function config_network() {
	dialog --infobox "Configuring network.." 0 0
	echo $hostname > /etc/hostname
	cat > /etc/hosts <<-EOF
		#<ip-address>   <hostname.domain.org>    <hostname>
		127.0.0.1       localhost.localdomain    localhost
		::1             localhost.localdomain    localhost
		127.0.1.1       ${hostname}.localdomain  $hostname
	EOF
}

function pacman_stuff() {
	dialog --infobox "Performance tweaks. (pacman/yay)" 0 0

	# Creates pacman hook to keep only the 3 latest versions of packages.
	cat > /etc/pacman.d/hooks/cleanup.hook <<-EOF
		[Trigger]
		Type = Package
		Operation = Remove
		Operation = Install
		Operation = Upgrade
		Target = *

		[Action]
		Description = Keeps only the latest 3 versions of packages
		When = PostTransaction
		Exec = /usr/bin/paccache -rk3
	EOF

	grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
	grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
}