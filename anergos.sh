#!/usr/bin/env bash
# License: GNU GPLv3

repo=https://raw.githubusercontent.com/ispanos/anergos/master
hostname=killua
name=yiannis
[ -z "$dotfilesrepo" ] 	&& dotfilesrepo="https://github.com/ispanos/dotfiles.git"
[ -z "$moz_repo" ] 		&& moz_repo="https://github.com/ispanos/mozzila"
# Usefull variables for arch.sh
# multi_lib_bool=
# user_password=
# root_password=
# multi_lib_bool=
# timezone=
# lang=

get_username() { 
	[ -z "$name" ] && read -rsep $'Please enter a name for a user account: \n' name
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		read -rsep $'Name not valid. Start with a letter, use lowercase letters, - or _ : \n' name
	done
	}

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
	echo "$lsb_dist"
	}

status_msg() { printf "%20s" $(tput setaf 3)"${FUNCNAME[1]}.... - "$(tput sgr0); }

ready() {
	echo $(tput setaf 2)"done"$@$(tput sgr0)
	}

nobeep() {
	status_msg
	echo "blacklist pcspkr" >> /etc/modprobe.d/blacklist.conf
	ready
	}

power_group() {
	status_msg
	gpasswd -a $name power >/dev/null 2>&1
	ready
	}

all_core_make() {
	status_msg
	grep -q "^MAKEFLAGS" /etc/makepkg.conf && ready "- '^MAKEFLAGS' exists" && return
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf; ready
	}

networkd_config() {
	status_msg
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

nano_configs() {
	status_msg
	grep -q '^include "/usr/share/nano/*.nanorc"' /etc/nanorc 2>&1 || 
	echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc && ready
	}

infinality(){
	status_msg
	if [ -r /etc/profile.d/freetype2.sh ]; then 
		sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh
		ready && return
	else
		echo $(tput setaf 1)"skipped"$(tput sgr0) && return
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
	ready " (value $1)"
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
		case $distro in
		arch)
			local g_utils="virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware"
			pacman -S --noconfirm $g_utils >/dev/null 2>&1

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
		sudo -u "$name" groups | grep -q vboxusers || 
			gpasswd -a $name vboxusers >/dev/null 2>&1
		ready " - host"
	fi
	}

resolv_conf() {
	status_msg
	printf "search home\\nnameserver 192.168.1.1\\n" > /etc/resolv.conf && ready
	}

enable_numlk_tty() {
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
		sudo -u "$name" yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
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

powerb_is_suspend() {
	status_msg
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
	ready
	}

nvidia_driver() {
	# Nouveau driver is broken for me at the moment.
	status_msg
	case $lsb_dist in
	arch)
		pacman -S --noconfirm nvidia nvidia-settings >/dev/null 2>&1
		if grep -q "^\[multilib\]" /etc/pacman.conf; then
			pacman -S --noconfirm lib32-nvidia-utils >/dev/null 2>&1
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
			printf "Removing orphans..."
			pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
			sudo -u "$name" pacman -Qq > /home/"$name"/.local/Fresh_pack_list
	 	;;
		*)
			echo $(tput setaf 1)"- Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac
	}

set_sane_permitions() {
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
echo "Wellcome to Anergos!"

# Archlinux installation. Not the greatest way to detect if arch.sh should run.
if [ "$(hostname)" = "archiso" ]; then
    curl -sL "$repo/anergos.d/arch.sh" 	> /tmp/arch.sh && source /tmp/arch.sh
else
	hostname=$(hostname)
fi

trap set_sane_permitions EXIT
# Needed Permissions
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel

get_username

# perform some very rudimentary platform detection
lsb_dist=$( get_distribution )
printf "$(tput setaf 3)Distribution	- $lsb_dist\n\n$(tput sgr0)"

nobeep; power_group; all_core_make; networkd_config; nano_configs; infinality
office_logo; clone_dotfiles; arduino_groups; agetty_set; lock_sleep

case $hostname in 
	killua)
		echo "killua:"
		create_swapfile; 	enable_numlk_tty; 	resolv_conf; 	virtualbox;
		powerb_is_suspend; 	firefox_configs; 	nvidia_driver;  temps; data;
	;;
	*)
		echo "Unknown hostname"
	;;
esac

catalog
exit
