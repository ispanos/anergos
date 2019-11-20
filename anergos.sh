#!/usr/bin/env bash
# License: GNU GPLv3

merge_lists() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi
	# Merges all csv files in one file. Checks for local files first.
	for file in $@; do
		if [ -r ${file}.csv ]; then
			cat ${lsb_dist}.${file}.csv >> /tmp/progs.csv
		elif [ -r programs/${file}.csv ]; then
			cat programs/${lsb_dist}.${file}.csv >> /tmp/progs.csv
		else
			curl -Ls "${progs_repo}/${lsb_dist}.${file}.csv" >> /tmp/progs.csv
		fi
	done
}


install_progs() {
	local packages=$(sed '/^#/d;/^,/d;s/,.*$//' /tmp/progs.csv | tr "\n" " ")
	local extra_repos=$(sed '/^#/d;/^,/d;s/^.*,//' /tmp/progs.csv)

	case $lsb_dist in
		manjaro)
			pacman -S --noconfirm --needed yay 
			yay --nodiffmenu --save
			yay -S --noconfirm --needed flatpak $packages
		;;
		arch)
			git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
			cd /tmp/yay && makepkg -si --noconfirm --needed
			yay --nodiffmenu --save
			yay -S --noconfirm --needed flatpak $packages
		;;
		raspbian | ubuntu)
			for ppa in $extra_repos; do
				sudo add-apt-repository ppa:$ppa -y
			done
			sudo apt install flatpak $packages
		;;
		fedora)
			for corp in $extra_repos; do
				sudo dnf copr enable $corp -y
			done
			sudo dnf install -y flatpak $packages
		;;
		*) printf "Distro is not supported yet.\n"
		;;
	esac
	sudo flatpak remote-add --if-not-exists \
		flathub https://flathub.org/repo/flathub.flatpakrepo
	# flatpak -y install flathub com.valvesoftware.Steam
	clear; printf "All programs have been installed...\n\n\n"; sleep 2
}


clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
    dotfilesrepo=$1
	local dir=$(mktemp -d)
    sudo chown -R "$USER" "$dir"
    cd $dir
	echo ".cfg" > .gitignore
	git clone -q --bare "$dotfilesrepo" $dir/.cfg
	git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null
    rm .gitignore
	cp -rfT . "/home/$USER/"
    cd /tmp
}


firefox_configs() {
	# Downloads firefox configs. Requires config repo.
	[ `command -v firefox` ] || return
	[ "$1" ] || return
	[ ! -d "/home/$USER/.mozilla/firefox" ] &&
	mkdir -p "/home/$USER/.mozilla/firefox" &&
	sudo chown -R "$USER" "/home/$USER/.mozilla/firefox"
	local dir=$(mktemp -d)
	sudo chown -R "$USER" "$dir"
	printf "\n\n\n\nCloning Firefox configs.\n"
	git clone -q --depth 1 "$1" "$dir/gitrepo" &&
	cp -rfT "$dir/gitrepo" "/home/$USER/.mozilla/firefox" && return
	echo "firefox_configs failed."
}


arduino_groups() {
	# Addes user to groups needed by arduino
	[ `command -v arduino` ] || return

	case $lsb_dist in

	arch)
		echo cdc_acm | sudo tee /etc/modules-load.d/cdcacm.conf >/dev/null
		groups | grep -q uucp || sudo gpasswd -a $USER uucp
		groups | grep -q lock || sudo gpasswd -a $USER lock
	;;
	ubuntu)
		groups | grep -q dialout || sudo gpasswd -a $USER dialout
	;;
	*) printf "Distro is not supported yet.\n"
	;;
	esac
}


agetty_set() {
	local ExexStart="ExecStart=-\/sbin\/agetty --skip-login --login-options"
	local log="$ExexStart $USER --noclear %I \$TERM"
	sed "s/^Exec.*/${log}/" /usr/lib/systemd/system/getty@.service |
		sudo tee /etc/systemd/system/getty@.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl reenable getty@tty1.service
}


virtualbox() {
	# If virtualbox is installed, adds user to vboxusers group
	[ `command -v virtualbox` ] && sudo usermod -aG vboxusers $USER

	[[ ! $(lspci | grep VirtualBox) ]] && return

	case $lsb_dist in
	arch) sudo pacman -S --noconfirm --needed \
	virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware ;;
	*) printf "Guest is not supported yet.\n"; sleep 2 ;;
	esac
}


it87_driver() { # Requires dkms
	# Installs driver for many Ryzen's motherboards temperature sensors
	local workdir="/home/$USER/.local/sources"
	mkdir -p "$workdir" && cd "$workdir"
	git clone -q https://github.com/bbqlinux/it87 &&
	cd it87 && sudo make dkms && sudo modprobe it87 &&
	echo "it87" | sudo tee /etc/modules-load.d/it87.conf >/dev/null
}


data() { # Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	sudo mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" | 
		sudo tee -a /etc/fstab >/dev/null
}


NvidiaDrivers() {
	# Installs proprietery Nvidia drivers for supported distros.
	[[ $(lspci | grep VirtualBox) ]] && return
	! lspci -k | grep -E "(VGA|3D)" | grep -q "NVIDIA" && return
	local gpu=$(lspci -k | grep -A 2 -E "(VGA|3D)" | 
		grep "NVIDIA" | awk -F'[][]' '{print $2}')
	printf '\n%.0s' {1..5}
	printf "Detected Nvidia GPU: $gpu \n"
	read -rep "Would you like to install the non-free Nvidia drivers?
	[ y/N]: "; [[ ! $REPLY =~ ^[Yy]$ ]] && return

	case $lsb_dist in

	arch) pacman -S --noconfirm --needed nvidia nvidia-settings
		grep -q "^\[multilib\]" /etc/pacman.conf &&
		pacman -S --noconfirm --needed lib32-nvidia-utils
	;;
	*) printf "Distro is not supported yet.\n"
	;;
	esac
}


catalog() {
	[ ! -d /home/"$USER"/.local ] && mkdir /home/"$USER"/.local

	case $lsb_dist in 

		manjaro | arch)
			sudo pacman --noconfirm -Rns $(pacman -Qtdq)
			pacman -Qq > /home/"$USER"/.local/Fresh_pack_list
	 	;;
		raspbian | ubuntu)
			sudo apt-get clean && sudo apt autoremove
			apt list --installed 2> /dev/null \
				> /home/"$USER"/.local/Fresh_pack_list
		;;
		fedora)
			dnf list installed > /home/"$USER"/.local/Fresh_pack_list
		;;
		*)
			printf "Distro is not supported yet.\n"
			return
		;;
	esac
}


if [ "$(id -nu)" == "root" ]; then
   cat <<-EOF
		This script changes your users configurations
		and should thus not be run as root.
		You may need to enter your password multiple times.
	EOF
	exit 1
fi

lsb_dist="$(. /etc/os-release && echo "$ID")"
printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"

# Preliminary configs for some distros.
case $lsb_dist in
	manjaro | arch)
	sudo pacman -Syu --noconfirm
	;;
    fedora) # I install using the "minimal-environment" (Server ISO)
        srtlnk="https://download1.rpmfusion.org"
        free="free/fedora/rpmfusion-free-release"
        nonfree="nonfree/fedora/rpmfusion-nonfree-release"
        sudo dnf install -y "$srtlnk/$free-$(rpm -E %fedora).noarch.rpm"
        sudo dnf install -y "$srtlnk/$nonfree-$(rpm -E %fedora).noarch.rpm"
        sudo dnf upgrade -y; sudo dnf remove -y openssh-server
    ;;
	ubuntu) 
		sudo apt-get update && sudo apt-get -y upgrade 
	;;
    *) echo "..."
	;;
esac

progs_repo=https://raw.githubusercontent.com/ispanos/anergos/master/programs
merge_lists $@ && install_progs

case $(hostnamectl | awk -F": " 'NR==1 {print $2}') in 
	killua) printf "\n\nkillua:\n"; it87_driver; data; agetty_set ;;
		 *) echo "Unknown hostname" ;;
esac

[ -f /usr/bin/docker ] && sudo usermod -aG docker $USER
NvidiaDrivers; arduino_groups; virtualbox; catalog
firefox_configs https://github.com/ispanos/mozzila
clone_dotfiles https://github.com/ispanos/dotfiles