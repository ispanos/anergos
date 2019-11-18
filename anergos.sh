#!/usr/bin/env bash
# License: GNU GPLv3

# Prints the name of the parent function or a prettified output.
status_msg() { printf "%-25s %2s" $(tput setaf 4)"${FUNCNAME[1]}"$(tput sgr0) "- "; }


# Prints "done" and any given arguments with a new line.
ready() { echo $(tput setaf 2)"done"$@$(tput sgr0); }

create_swapfile() {
	# Creates a swapfile. 2Gigs in size.
	status_msg
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile >/dev/null 2>&1
	swapon /swapfile
	printf "\\n/swapfile none swap defaults 0 0\\n" >> /etc/fstab
	printf "vm.swappiness=10\\nvm.vfs_cache_pressure=50" > /etc/sysctl.d/99-sysctl.conf
	ready
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
			cat programs/${lsb_dist}.${file}.csv >> /tmp/progs.csv
		else
			curl -Ls "${programs_repo}${lsb_dist}.${file}.csv" >> /tmp/progs.csv
		fi
	done
    sudo -u "$name" yay -S --noconfirm --needed $(cat /tmp/progs.csv | sed '/^#/d;/^,/d;s/,.*$//' | tr "\n" " ")
}


clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
	dotfilesrepo=$1
	status_msg
	local dir=$(mktemp -d)
    chown -R "$name:wheel" "$dir"
    cd $dir
	echo ".cfg" > .gitignore
	sudo -u "$name" git clone -q --bare "$dotfilesrepo" $dir/.cfg
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null 2>&1
    rm .gitignore
	sudo -u "$name" cp -rfT . "/home/$name/"
    cd /tmp
	ready
}


firefox_configs() {
	# Downloads firefox configs. Only useful if you upload your configs on github.
	[ `command -v firefox` ] || return
	[ "$1" ] || return

	status_msg

	if [ ! -d "/home/$name/.mozilla/firefox" ]; then
		mkdir -p "/home/$name/.mozilla/firefox"
		chown -R "$name:wheel" "/home/$name/.mozilla/firefox"
	fi

	local dir=$(mktemp -d)
	chown -R "$name:wheel" "$dir"
	sudo -u "$name" git clone -q --depth 1 "$1" "$dir/gitrepo" &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "/home/$name/.mozilla/firefox" &&
	ready && return

	echo "firefox_configs failed."
}


arduino_groups() {
	# Addes user to groups needed by arduino
	[ `command -v arduino` ] || return

	status_msg
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep -q uucp || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep -q lock || gpasswd -a $name lock >/dev/null 2>&1
	ready
}


agetty_set() {
	systemctl enable --now gdm >/dev/null 2>&1 && ready " GDM enabled" && return
	status_msg
	local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service
	systemctl daemon-reload >/dev/null 2>&1
	systemctl reenable getty@tty1.service >/dev/null 2>&1
	ready "$1"
}


virtualbox() {
	# If on V/box, removes v/box from the guest and installs guest-utils.
	# If virtualbox is installed, adds user to vboxusers group
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

	elif [ `command -v virtualbox` ]; then
		printf "Host -"
		gpasswd -a $name vboxusers >/dev/null 2>&1
	fi
	ready
}


it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	# Requires dkms
	status_msg
	local workdir="/home/$name/.local/sources"
	sudo -u "$name" mkdir -p "$workdir"
	cd "$workdir"
	sudo -u "$name" git clone -q https://github.com/bbqlinux/it87
	cd it87 || echo "Failed" && return
	make dkms
	modprobe it87
	echo "it87" > /etc/modules-load.d/it87.conf
	ready
}


data() {
	# Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" >> /etc/fstab
}


nvidia_drivers() {
	# Installs proprietery Nvidia drivers for supported distros.
	# Returns with no output, if the installation is in VirutalBox.

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


catalog() {
	# Removes orphan pacakges and makes a list of all installed packages 
	# at ~/.local/Fresh_pack_list used to track new installed /uninstalled packages
	
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
						> /home/"$name"/.local/Fresh_pack_list
		;;
		*)
			printf $(tput setaf 1)"Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac

	ready
}



[ "$(id -nu)" != "root" ] && read -rp "This script must be run as root." && 
exit

[ "$( hostnamectl | awk -F": " 'NR==1 {print $2}' )" != "archiso" ] &&
read -rp "This script is meant to run on a fresh Archlinux installation." &&
exit

clear

repo=https://raw.githubusercontent.com/ispanos/anergos/master
package_lists="$@"

lsb_dist="$(. /etc/os-release && echo "$ID")"

printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"

install_progs "$package_lists"

systemctl enable NetworkManager || networkd_config
printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc

[ -f /usr/bin/docker ] && gpasswd -a $name docker >/dev/null 2>&1
[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# Configurations are picked according to the hostname of the computer.
case $hostname in 
	killua)
		printf "\n\nkillua:\n"
		it87_driver; data; nvidia_drivers; create_swapfile;
		agetty_set; arduino_groups; virtualbox; catalog;
		firefox_configs https://github.com/ispanos/mozzila
		clone_dotfiles https://github.com/ispanos/dotfiles
	;;
	*)
		echo "Unknown hostname"
	;;
esac
