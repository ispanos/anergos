#!/usr/bin/env bash
# License: GNU GPLv3

repo=https://raw.githubusercontent.com/ispanos/anergos/master
hostname=killua
name=yiannis
[ -z "$dotfilesrepo" ] 	&& dotfilesrepo="https://github.com/ispanos/dotfiles.git"
[ -z "$moz_repo" ] 		&& moz_repo="https://github.com/ispanos/mozzila"
# Usefull variables for arch.sh
# user_password=
# root_password=
[ -z "$programs_repo" ]  	&& programs_repo="$repo/programs/"
[ -z "$multi_lib_bool" ] 	&& multi_lib_bool=true
[ -z "$timezone" ] 			&& timezone="Europe/Athens"
[ -z "$lang" ] 				&& lang="en_US.UTF-8"

get_username() { 
	[ -z "$name" ] && read -rsep $'Please enter a name for a user account: \n' name
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		read -rsep $'Invalid name. Start with a letter, use lowercase letters, - or _ : \n' name
	done
	}

## Archlinux installation
get_user_info() { 
	if [ -z "$hostname" ]; then
	    read -rsep $'Enter computer\'s hostname: \n' hostname
	fi
	get_username
    if [ -z "$user_password" ]; then
        read -rsep $"Enter a password for $name: " user_password && echo
        read -rsep $"Retype ${name}s password: " check_4_pass && echo
        while ! [ "$user_password" = "$check_4_pass" ]; do unset check_4_pass
            read -rsep $"Passwords didn't match. Retype ${name}'s password: " user_password && echo
            read -rsep $"Retype ${name}'s password: " check_4_pass  && echo
        done
        unset check_4_pass
    fi
    if [ -z "$root_password" ]; then
        read -rsep $'Enter root\'s password: \n' root_password
        read -rsep $'Retype root user password: \n' check_4_pass
        while ! [ "$root_password" = "$check_4_pass" ]; do unset check_4_pass
            read -rsep $'Passwords didn\'t match. Retype root user password: \n' root_password
            read -rsep $'Retype root user password: \n' check_4_pass
        done
        unset check_4_pass
    fi
	}

systemd_boot() {
	bootctl --path=/boot install >/dev/null 2>&1
	cat > /boot/loader/loader.conf <<-EOF
		default  arch
		console-mode max
		editor   no
	EOF
	local id="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"
	cat > /boot/loader/entries/arch.conf <<-EOF
		title   Arch Linux
		linux   /vmlinuz-linux
		initrd  /${cpu}-ucode.img
		initrd  /initramfs-linux.img
		options root=${id} rw quiet
	EOF
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
	}

grub_mbr() {
	pacman --noconfirm --needed -S grub >/dev/null 2>&1
	grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
	grub-install --target=i386-pc $grub_path >/dev/null 2>&1
	grub-mkconfig -o /boot/grub/grub.cfg
	}

core_arch_install() {
	echo ":: Setting up Arch..."
	systemctl enable systemd-timesyncd.service >/dev/null 2>&1
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
	# Install cpu microcode.
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
	esac
	pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
	# Install bootloader
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot && pacman --needed --noconfirm -S efibootmgr > /dev/null 2>&1
	else
		grub_mbr
	fi
	# Set root password, create user and set user password.
	printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$user_password" | chpasswd
	}

install_devel_git() {
	for package in base-devel git; do
		echo ":: Installing - $package"
		pacman --noconfirm --needed -S $package >/dev/null 2>&1
	done
	}

install_yay() {
	echo ":: Installing - yay-bin" # Requires user (core_arch_install), base-devel, permitions.
	cd /tmp ; sudo -u "$name" git clone https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1
	cd yay-bin && sudo -u "$name" makepkg -si --noconfirm >/dev/null 2>&1
	}

install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi

	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	[ "$multi_lib_bool" = true  ] && sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf &&
	echo ":: Synchronizing package databases..." && pacman -Sy >/dev/null 2>&1

	for i in "$@"; do 
		curl -Ls "${programs_repo}${i}.csv" | sed '/^#/d' >> /tmp/progs.csv
	done
	total=$(wc -l < /tmp/progs.csv)
	echo  "Installing packages from csv file(s): $@"
	while IFS=, read -r tag program comment; do ((n++))
		echo "$comment" | grep -q "^\".*\"$" && 
		comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		printf "%07s %-23s %2s %2s" "[$n""/$total]" "$(basename $program)" - "$comment"
		case "$tag" in
			"") printf '\n'
				pacman --noconfirm --needed -S "$program" > /dev/null 2>&1 ||
				echo "$program" >> /home/${name}/failed
			;;
			"A") printf "(AUR)\n"
				sudo -u "$name" yay -S --needed --noconfirm "$program" >/dev/null 2>&1 ||
				echo "$program" >> /home/${name}/failed	
			;;
			"G") printf "(GIT)\n"
				local dir=$(mktemp -d)
				git clone --depth 1 "$program" "$dir" > /dev/null 2>&1
				cd "$dir" && make >/dev/null 2>&1
				make install >/dev/null 2>&1 || echo "$program" >> /home/${name}/failed 
				cd /tmp
			;;
			"P") printf "(PIP)\n"
				command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
				yes | pip install "$program" || echo "$program" >> /home/${name}/failed
			;;
		esac
	done < /tmp/progs.csv
	}

extra_arch_configs() {
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
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf
	printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc
	}
## Archlinux installation end

status_msg() { printf "%-20s %2s" $(tput setaf 3)"${FUNCNAME[1]}" "- "$(tput sgr0); }

ready() { echo $(tput setaf 2)"done"$@$(tput sgr0); }

nobeep() { status_msg; echo "blacklist pcspkr" >> /etc/modprobe.d/blacklist.conf; ready; }

power_group() { status_msg; gpasswd -a $name power >/dev/null 2>&1; ready; }

networkd_config() {
	status_msg
	systemctl stop dhcpcd 		>/dev/null 2>&1
	systemctl disable dhcpcd 	>/dev/null 2>&1
	if [ -f  /usr/bin/NetworkManager ]; then
		systemctl enable NetworkManager >/dev/null 2>&1
		ready " (NetworkManager)"

	else
		net_devs=$(networkctl --no-legend 2>/dev/null | grep -P "ether|wlan" | awk '{print $2}')
		for device in ${net_devs[*]}; do ((i++))
			cat > /etc/systemd/network/${device}.network <<-EOF
				[Match]
				Name=${device}
				[Network]
				DHCP=ipv4
				[DHCP]
				RouteMetric=$(($i * 10))
			EOF
		done
		systemctl enable systemd-networkd >/dev/null 2>&1
		systemctl enable systemd-resolved >/dev/null 2>&1
		ready
	fi 
	}

infinality(){
	status_msg
	if [ -r /etc/profile.d/freetype2.sh ]; then 
		sed -i 's/^#exp/exp/;s/version=40"$/version=38"/' /etc/profile.d/freetype2.sh
		ready
	else
		echo $(tput setaf 1)"skipped (freetype2 is not installed)"$(tput sgr0)
	fi
	}

office_logo() {
	status_msg
	[ -f /etc/libreoffice/sofficerc ] || echo "Skipped - /etc/libreoffice missing" && return
	sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc && ready
	}

create_swapfile() {
	status_msg
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile >/dev/null 2>&1
	swapon /swapfile
	printf "# Swapfile\\n/swapfile none swap defaults 0 0\\n\\n" >> /etc/fstab
	printf "vm.swappiness=10\nvm.vfs_cache_pressure=50\n" > /etc/sysctl.d/99-sysctl.conf
	ready
	}

clone_dotfiles() {
	status_msg
	cd /home/"$name" && echo ".cfg" >> .gitignore && rm .bash_profile .bashrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config \
				--local status.showUntrackedFiles no > /dev/null 2>&1 && rm .gitignore
	ready
	}

firefox_configs() {
	[ ! -f /usr/bin/firefox ] && return
	status_msg
	[ -z "$moz_repo" ] && echo "Repository not set." && return
	if [ ! -d "/home/$name/.mozilla/firefox" ]; then
		mkdir -p "/home/$name/.mozilla/firefox"
		chown -R "$name:wheel" "/home/$name/.mozilla/firefox"
	fi
	local dir=$(mktemp -d)
	chown -R "$name:wheel" "$dir"
	sudo -u "$name" git clone --depth 1 "$moz_repo" "$dir/gitrepo" &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "/home/$name/.mozilla/firefox" &&
	ready && return
	echo "firefox_configs failed."
	}

arduino_groups() {
	status_msg
	[ ! -f /usr/bin/arduino ] && echo "Skipped - /usr/bin/arduino missing." && return
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep -q uucp || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep -q lock || gpasswd -a $name lock >/dev/null 2>&1
	ready
	}

agetty_set() {
	systemctl enable gdm >/dev/null 2>&1 && ready " GDM (value $1)" && return
	status_msg
	if [ "$1" = "auto" ]; then
		local log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \$TERM"
	else
		local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	fi
	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service
	systemctl daemon-reload >/dev/null 2>&1; systemctl reenable getty@tty1.service >/dev/null 2>&1
	ready "$1"
	}

lock_sleep() {
	status_msg
	if [ -f /usr/bin/i3lock ] && [ ! -f /usr/bin/sway ]; then
		cat > /etc/systemd/system/SleepLocki3@${name}.service <<-EOF
			#/etc/systemd/system/
			[Unit]
			Description=Turning i3lock on before sleep
			Before=sleep.target
			[Service]
			User=%I
			Type=forking
			Environment=DISPLAY=:0
			ExecStart=/usr/bin/i3lock -e -f -c 000000 -i /home/${name}/.config/wall.png -t
			ExecStartPost=/usr/bin/sleep 1
			[Install]
			WantedBy=sleep.target
		EOF
	fi
	systemctl enable SleepLocki3@${name} >/dev/null 2>&1
	ready
	}

virtualbox() {
	status_msg

	if [[ $(lspci | grep VirtualBox) ]]; then
		case $lsb_dist in
		arch)
			local g_utils="virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware"
			pacman -S --noconfirm --needed $g_utils >/dev/null 2>&1

			if [ -f /usr/bin/virtualbox ]; then
				printf "Removing VirtualBox... "
				pacman -Rns --noconfirm virtualbox >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-host-modules-arch >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-guest-iso >/dev/null 2>&1 
			fi
			ready " - guest"
		;;
		*)
			echo $(tput setaf 1)"- Guest is not supported yet."$(tput sgr0)
		;;
		esac
	elif [ -f /usr/bin/virtualbox ]; then
		sudo -u "$name" groups | grep -q vboxusers || gpasswd -a $name vboxusers >/dev/null 2>&1
		ready " - host"
	fi
	}

resolv_conf() {
	status_msg
	printf "search home\\nnameserver 192.168.1.1\\n" > /etc/resolv.conf && ready
	}

numlockTTY() {
	status_msg
	cat > /etc/systemd/system/numLockOnTty.service <<-EOF
		[Unit]
		Description=numlockOnTty
		[Service]
		ExecStart=/usr/bin/numlockOnTty
		[Install]
		WantedBy=multi-user.target
	EOF
	cat > /usr/bin/numlockOnTty <<-EOF
		#!/usr/bin/env bash

		for tty in /dev/tty{1..6}
		do
		    /usr/bin/setleds -D +num < "$tty";
		done

	EOF
	chmod +x /usr/bin/numlockOnTty; systemctl enable numLockOnTty >/dev/null 2>&1
	ready
	}

temps() { # https://aur.archlinux.org/packages/it87-dkms-git || github.com/bbqlinux/it87
	status_msg
	case $lsb_dist in
	arch)
		[ ! -f /usr/bin/yay ] && "Skipped - yay not installed." && return
		sudo -u "$name" yay -S --noconfirm --needed it87-dkms-git >/dev/null 2>&1
		echo "it87" > /etc/modules-load.d/it87.conf
		ready 
	;;
	*)
		echo $(tput setaf 1)"- Guest is not supported yet."$(tput sgr0) 
		return 
	;;
	esac
	}

data() {
	status_msg
	mkdir -p /media/Data
	cat >> /etc/fstab <<-EOF
		# /dev/sda1 LABEL=data
		UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4 /media/Data ext4 rw,noatime,nofail,user,auto 0 2
	
	EOF
	ready
	}

power_to_sleep() {
	status_msg
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
	ready
	}

nvidia_drivers() {
	[[ $(lspci | grep VirtualBox) ]] && return
	# Nouveau driver is broken for me at the moment.
	status_msg
	case $lsb_dist in
	arch)
		pacman -S --noconfirm --needed nvidia nvidia-settings >/dev/null 2>&1
		if grep -q "^\[multilib\]" /etc/pacman.conf; then
			pacman -S --noconfirm --needed lib32-nvidia-utils >/dev/null 2>&1
		fi
		ready 
	;;
	*)
		echo $(tput setaf 1)"- Guest is not supported yet."$(tput sgr0) 
		return 
	;;
	esac
	}

catalog() {
	status_msg
	[ ! -d /home/"$name"/.local ] && sudo -u "$name" mkdir /home/"$name"/.local
	case $lsb_dist in 
		arch)
			echo "Removing orphans..."
			pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
			sudo -u "$name" pacman -Qq > /home/"$name"/.local/Fresh_pack_list
	 	;;
		*)
			echo $(tput setaf 1)"- Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac
	}

set_needed_perms() {
	# This is needed for using sudo with no password in the rest of the scirpt.
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
	}

set_sane_perms() {
grep -q "NOPASSWD: ALL" /etc/sudoers.d/wheel || return
cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel
echo $(tput setaf 2)"${FUNCNAME[0]}- in $0 Done!"$(tput sgr0)
sleep 5
}

clear
[ "$(id -nu)" != "root" ] && echo "This script must be run as root." && exit
[ -r /etc/os-release ] && lsb_dist="$(. /etc/os-release && echo "$ID")"
printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"

trap set_sane_perms EXIT

if [ "$(hostname)" = "archiso" ]; then
	# Archlinux installation. Not the greatest way to detect if arch.sh should run.
	get_user_info
	core_arch_install
	install_devel_git
	set_needed_perms
	install_yay
	install_progs "$@"
	extra_arch_configs
else
	hostname=$(hostname)
	get_username
	set_needed_perms
fi

case $hostname in 
	killua)
		echo "killua:"
		numlockTTY; power_to_sleep; power_group; infinality; nobeep;   
		virtualbox; clone_dotfiles; office_logo; firefox_configs;
		agetty_set; arduino_groups; resolv_conf; create_swapfile;
		lock_sleep; nvidia_drivers; temps; data; networkd_config;
	;;
	*)
		echo "Unknown hostname"
	;;
esac

catalog && exit
