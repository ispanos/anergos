#!/bin/bash

function set_locale_time() {
	systemctl enable systemd-timesyncd.service
	ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
	hwclock --systohc
	sed -i "s/#${lang} UTF-8/${lang} UTF-8/g" /etc/locale.gen
	locale-gen > /dev/null 2>&1
	echo 'LANG="'$lang'"' > /etc/locale.conf
}

function config_network() {
	echo $hostname > /etc/hostname
	cat > /etc/hosts <<-EOF
		#<ip-address>   <hostname.domain.org>    <hostname>
		127.0.0.1       localhost.localdomain    localhost
		::1             localhost.localdomain    localhost
		127.0.1.1       ${hostname}.localdomain  $hostname
	EOF
}

function get_microcode() {
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
		*)				cpu="no" 	;;
	esac

	if [ $cpu != "no" ]; then
		pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
	fi
}

function systemd_boot() {
	# Installs systemd-boot to the eps partition
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

	# sets id as the UUID of the partition mounted at "/".
	id="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"

	# Creates loader entry for root partition, using the "linux" kernel
						echo "title   Arch Linux"           >  /boot/loader/entries/arch.conf
						echo "linux   /vmlinuz-linux"       >> /boot/loader/entries/arch.conf
	[ $cpu = "no" ] || 	echo "initrd  /${cpu}-ucode.img"    >> /boot/loader/entries/arch.conf
						echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
						echo "options root=${id} rw quiet"  >> /boot/loader/entries/arch.conf
}

function grub_mbr() {
		pacman --noconfirm --needed -S grub >/dev/null 2>&1
		grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
		grub-install --target=i386-pc $grub_path >/dev/null 2>&1
		grub-mkconfig -o /boot/grub/grub.cfg
}

function inst_bootloader() {
	dialog --infobox "Installing bootloader." 3 28
	get_microcode
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot && pacman --needed --noconfirm -S efibootmgr > /dev/null 2>&1
	else
		grub_mbr
	fi
}

function set_root_pw() {
	printf "${rpwd1}\\n${rpwd1}" | passwd >/dev/null 2>&1
	unset rpwd1 rpwd2
}

function vanila_arch() {
	set_locale_time
	config_network
	inst_bootloader
	set_root_pw
}

function pacman_stuff() {
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

function create_user() {
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$upwd1" | chpasswd
	unset upwd1 upwd2
}

function get_deps() {
	dialog --title "First things first." --infobox "Installing 'base-devel' and 'git'." 3 40
	pacman --noconfirm --needed -S  git base-devel >/dev/null 2>&1
	grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
}

function yay_install() {
	# Requires user.
	dialog --infobox "Installing yay..." 4 50
	cd /tmp && curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz
	sudo -u ${name} tar -xvf yay.tar.gz >/dev/null 2>&1
	cd yay && sudo -u ${name} makepkg --needed --noconfirm -si >/dev/null 2>&1
	cd /tmp || return
}

function mergeprogsfiles() {
	for list in ${prog_files}; do
		if [ -f "$list" ]; then
			cat "$list" >> /tmp/progs.csv
		else
			curl -Ls "$list" | sed '/^#/d' >> /tmp/progs.csv
		fi
	done
}

function multilib() {
	# Enables multilib if flag -m is used.
	if [ "$multi_lib_bool" ]; then
		dialog --infobox "Enabling multilib..." 0 0
		sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
		pacman --noconfirm --needed -Sy >/dev/null 2>&1
		pacman -Fy >/dev/null 2>&1
	fi
}

function maininstall() { # Installs all needed programs from main repo.
	dialog --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	pacman --noconfirm --needed -S "$1" > /dev/null 2>&1
}

function aurinstall() {
	dialog  --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep "^$1$" > /dev/null 2>&1 && return
	sudo -u "$name" yay -S --noconfirm "$1" >/dev/null 2>&1
}

function gitmakeinstall() {
	dir=$(mktemp -d)
	dialog  --infobox "Installing \`$(basename "$1")\` ($n of $total). $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" > /dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return
}

function pipinstall() {
	dialog --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

function installationloop() {
	get_deps
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel
	yay_install
	mergeprogsfiles
	multilib

	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qm | awk '{print $1}')
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"")  maininstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"A") aurinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"G") gitmakeinstall "$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"P") pipinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		esac
	done < /tmp/progs.csv
}

function create_pack_ref() {
	dialog --infobox "Removing orphans..." 0 0
	pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
	sudo -u "$name" mkdir -p /home/"$name"/.local/
	pacman -Qq > /home/"$name"/.local/Fresh_pack_list
}

function pacman_group() {
	groupadd pacman
	gpasswd -a "$name" pacman
	echo "%pacman ALL=(ALL) NOPASSWD: /usr/bin/pacman -Syu" > /etc/sudoers.d/pacman
	chmod 440 /etc/sudoers.d/pacman
}

vanila_arch

pacman_stuff
create_user
installationloop
create_pack_ref
pacman_group