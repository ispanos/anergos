#!/usr/bin/env bash
# License: GNU GPLv3

hostname=killua; name=yiannis; repo=https://raw.githubusercontent.com/ispanos/anergos/master
[ -z "$dotfilesrepo" ] 		&& dotfilesrepo="https://github.com/ispanos/dotfiles"
[ -z "$moz_repo" ] 			&& moz_repo="https://github.com/ispanos/mozzila"
[ -z "$programs_repo" ]  	&& programs_repo="$repo/programs/"
[ -z "$multi_lib_bool" ] 	&& multi_lib_bool=true
[ -z "$timezone" ] 			&& timezone="Europe/Athens"
[ -z "$lang" ] 				&& lang="en_US.UTF-8"
[ -r /etc/os-release ] 		&& lsb_dist="$(. /etc/os-release && echo "$ID")"

package_lists="$@"

[ "$(id -nu)" != "root" ] 	&& echo "This script must be run as root." && exit
clear

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

	local root_id="$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"

	# https://forum.manjaro.org/t/amd-ryzen-problems-and-fixes/55533
	cat > /boot/loader/entries/arch.conf <<-EOF
		title   Arch Linux
		linux   /vmlinuz-linux
		initrd  /${cpu}-ucode.img
		initrd  /initramfs-linux.img
		options root=UUID=${root_id} rw quiet idle=nomwait
	EOF

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

quick_install() {
	# For quick installation of arch-only packages.
	for package in $@; do
		echo ":: Installing - $package"
		pacman --noconfirm --needed -S $package >/dev/null 2>&1
	done
	}
	
grub_mbr() {
	quick_install grub
	# pacman --noconfirm --needed -S grub >/dev/null 2>&1
	grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
	grub-install --target=i386-pc $grub_path >/dev/null 2>&1
	grub-mkconfig -o /boot/grub/grub.cfg
	}

core_arch_install() {
	echo ":: Setting up Arch"
	
	systemctl enable --now systemd-timesyncd.service >/dev/null 2>&1
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

	quick_install "${cpu}-ucode"
	# pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
	
	# This folder is needed for pacman hooks. (needed for systemd-boot)
	mkdir -p /etc/pacman.d/hooks

	# Install bootloader
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot
		quick_install efibootmgr
		# pacman --needed --noconfirm -S efibootmgr > /dev/null 2>&1
	else
		grub_mbr
	fi

	# Enable [multilib] repo, if multi_lib_bool == true and sync database. -Sy
	if [ "$multi_lib_bool" = true  ]; then
		sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
		echo ":: Synchronizing package databases - [multilib]"
		pacman -Sy >/dev/null 2>&1
	fi

	# Set root password, create user and set user password.
	printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$user_password" | chpasswd
	}

install_yay() {
	# Requires user (core_arch_install), base-devel, permitions.
	echo ":: Installing - yay-bin"
	cd /tmp
	sudo -u "$name" git clone https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1
	cd yay-bin && 
	sudo -u "$name" makepkg -si --noconfirm >/dev/null 2>&1
	}

install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi

	# Use all cpu cores to compile packages
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

	# Merges all csv files in one file. Checks for local files first.
	for file in $@; do
		if [ -r programs/${file}.csv ]; then
			cat programs/${file}.csv | sed '/^#/d' >> /tmp/progs.csv
		else
			curl -Ls "${programs_repo}${file}.csv" | sed '/^#/d' >> /tmp/progs.csv
		fi
	done

	total=$(wc -l < /tmp/progs.csv)

	echo  "Installing packages from csv file(s): $@"

	while IFS=, read -r tag program comment; do ((n++))
		echo "$comment" | grep -q "^\".*\"$" && 
			comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"

		printf "%07s %-20s %2s %2s" "[$n""/$total]" "$(basename $program)" - "$comment"

		case "$tag" in
			"") printf '\n'
				pacman --noconfirm --needed -S "$program" > /dev/null 2>&1 ||
				echo "$(tput setaf 1)$program failed$(tput sgr0)" | tee /home/${name}/failed
			;;
			"A") printf "(AUR)\n"
				sudo -u "$name" yay -S --needed --noconfirm "$program" >/dev/null 2>&1 ||
				echo "$(tput setaf 1)$program failed$(tput sgr0)" | tee /home/${name}/failed
			;;
			"G") printf "(GIT)\n"
				local dir=$(mktemp -d)
				git clone --depth 1 "$program" "$dir" > /dev/null 2>&1
				cd "$dir" && make >/dev/null 2>&1
				make install >/dev/null 2>&1 ||
				echo "$(tput setaf 1)$program failed$(tput sgr0)" | tee /home/${name}/failed
			;;
			"P") printf "(PIP)\n"
				command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
				yes | pip install "$program" ||
				echo "$(tput setaf 1)$program failed$(tput sgr0)" | tee /home/${name}/failed
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

status_msg() { printf "%-25s %2s" $(tput setaf 4)"${FUNCNAME[1]}"$(tput sgr0) "- "; }

ready() { echo $(tput setaf 2)"done"$@$(tput sgr0); }

nobeep() { status_msg; echo "blacklist pcspkr" >> /etc/modprobe.d/blacklist.conf; ready; }

power_group() { status_msg; gpasswd -a $name power >/dev/null 2>&1; ready; }

resolv_conf() { printf "search home\\nnameserver 192.168.1.1\\n" > /etc/resolv.conf ; }

networkd_config() {
	status_msg

	#systemctl stop dhcpcd 		>/dev/null 2>&1
	systemctl disable --now dhcpcd 	>/dev/null 2>&1

	if [ -f  /usr/bin/NetworkManager ]; then
		systemctl enable --now NetworkManager >/dev/null 2>&1
		ready " (NetworkManager)"
		return
	fi

	net_devs=$( networkctl --no-legend 2>/dev/null | \
				grep -P "ether|wlan" | \
				awk '{print $2}' | \
				sort )

	for device in ${net_devs[*]}; do ((i++))
		cat > /etc/systemd/network/${device}.network <<-EOF
			[Match]
			Name=${device}

			[Network]
			DHCP=ipv4
			IPForward=yes

			[DHCP]
			RouteMetric=$(($i * 10))

		EOF
	done

	systemctl enable --now systemd-networkd >/dev/null 2>&1
	systemctl enable --now systemd-resolved >/dev/null 2>&1
	ready
	}

infinality(){
	[ ! -r /etc/profile.d/freetype2.sh ] && return
	status_msg
	sed -i 's/^#exp/exp/;s/version=40"$/version=38"/' /etc/profile.d/freetype2.sh
	ready
	}

office_logo() {
	[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc
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
	[ -z "$dotfilesrepo" ] && return
	status_msg

	cd /home/"$name"
	echo ".cfg" >> .gitignore
	rm .bash_profile .bashrc

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
	[ ! -f /usr/bin/arduino ] && return

	status_msg
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep -q uucp || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep -q lock || gpasswd -a $name lock >/dev/null 2>&1
	ready
	}

agetty_set() {
	systemctl enable --now gdm >/dev/null 2>&1 && ready " GDM enabled" && return

	status_msg

	if [ "$1" = "auto" ]; then
		local log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \$TERM"
	else
		local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	fi

	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service

	systemctl daemon-reload >/dev/null 2>&1
	systemctl reenable getty@tty1.service >/dev/null 2>&1
	ready "$1"
	}

i3lock_sleep() {
	status_msg

	# This should be replaced with something better.
	if [ -f /usr/bin/i3lock ]; then
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

	[ -f /usr/bin/sway ] && return
	systemctl enable --now SleepLocki3@${name} >/dev/null 2>&1
	ready
	}

virtualbox() {
	status_msg

	if [[ $(lspci | grep VirtualBox) ]]; then
		printf "Guest -"

		case $lsb_dist in
		arch)
			local g_utils="virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware"
			pacman -S --noconfirm --needed $g_utils >/dev/null 2>&1

			[ ! -f /usr/bin/virtualbox ] && ready && return
			printf "Removing VirtualBox "
			pacman -Rns --noconfirm virtualbox >/dev/null 2>&1
			pacman -Rns --noconfirm virtualbox-host-modules-arch >/dev/null 2>&1
			pacman -Rns --noconfirm virtualbox-guest-iso >/dev/null 2>&1 
		;;
		*)
			echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0)
			return
		;;
		esac

	elif [ -f /usr/bin/virtualbox ]; then
		printf "Host -"
		gpasswd -a $name vboxusers >/dev/null 2>&1
	fi
	ready
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

	chmod +x /usr/bin/numlockOnTty
	systemctl enable --now numLockOnTty >/dev/null 2>&1
	ready
	}

temps() { 
	# https://aur.archlinux.org/packages/it87-dkms-git || github.com/bbqlinux/it87
	status_msg

	case $lsb_dist in
	manjaro | arch)
		[ ! -f /usr/bin/yay ] && "Skipped - yay not installed." && return
		sudo -u "$name" yay -S --noconfirm --needed it87-dkms-git >/dev/null 2>&1
		echo "it87" > /etc/modules-load.d/it87.conf
		ready 
	;;
	*)
		echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0)
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
	sed -i '/HandlePowerKey/{s/=.*$/=suspend/;s/^#//}' /etc/systemd/logind.conf
	ready
	}

nvidia_drivers() {
	# returns if the installation is in VirutalBox. 
	[[ $(lspci | grep VirtualBox) ]] && return
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
		echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0) 
		return 
	;;
	esac
	}

Install_vim_plugged_plugins() {
	status_msg
	# Not tested.
	sudo -u "$name" mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
									> "/home/$name/.config/nvim/autoload/plug.vim"
	(sleep 30 && killall nvim) &
	sudo -u "$name" nvim -E -c "PlugUpdate|visual|q|q" >/dev/null 2>&1
	ready
	}

safe_ssh() {
	sed -i '/#PasswordAuthentication/{s/yes/no/;s/^#//}' /etc/ssh/sshd_config
	# systemctl enable --now sshd
	}

catalog() {
	status_msg
	[ ! -d /home/"$name"/.local ] && sudo -u "$name" mkdir /home/"$name"/.local
	
	case $lsb_dist in 
		manjaro | arch)
			pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
			sudo -u "$name" pacman -Qq > /home/"$name"/.local/Fresh_pack_list
	 	;;
		raspbian | ubuntu)
			sudo apt-get clean >/dev/null 2>&1
			sudo apt autoremove >/dev/null 2>&1
			sudo -u "$name" apt list --installed 2> /dev/null |
				awk -F/ '{print $1}' > /home/"$name"/.local/Fresh_pack_list
		;;
		*)
			printf $(tput setaf 1)"Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac

	ready
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
echo $(tput setaf 2)"Proper permissions set"$(tput sgr0)
echo "All done! - exiting"
sleep 5
}

# Sets sensible permitions when script exits.
trap set_sane_perms EXIT

printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"

if [ "$( hostnamectl | awk -F": " 'NR==1 {print $2}' )" = "archiso" ]; then
	# Archlinux installation.
	get_user_info
	core_arch_install
	quick_install base-devel linux linux-headers pacman-contrib expac git arch-audit
	set_needed_perms
	install_yay
	install_progs "$package_lists"
	extra_arch_configs
else
	# Non Archlinux settings.
	hostname=$( hostnamectl | awk -F": " 'NR==1 {print $2}' )
	get_username
	set_needed_perms
fi

# All configurations are picked according to the hostname of the computer.
case $hostname in 
	killua)
		printf "\n\nkillua:\n"
		numlockTTY; power_to_sleep; power_group; i3lock_sleep; nobeep;
		virtualbox; clone_dotfiles; office_logo; firefox_configs;
		agetty_set; arduino_groups; resolv_conf; create_swapfile;
		infinality; nvidia_drivers; temps; data; networkd_config;
	;;
	leorio)
		power_group; nobeep; clone_dotfiles; firefox_configs;
		agetty_set; arduino_groups; networkd_config;
	;;
	*)
		echo "Unknown hostname"
	;;
esac

clone_dotfiles
catalog
