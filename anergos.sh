#!/usr/bin/env bash
# License: GNU GPLv3

install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi
	# Use all cpu cores to compile packages
	sudo sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

	# Merges all csv files in one file. Checks for local files first.
	for file in $@; do
		if [ -r ${file}.csv ]; then
			cat ${lsb_dist}.${file}.csv >> /tmp/progs.csv
		elif [ -r programs/${file}.csv ]; then
			cat programs/${lsb_dist}.${file}.csv >> /tmp/progs.csv
		else
			curl -Ls "${programs_repo}${lsb_dist}.${file}.csv" >> /tmp/progs.csv
		fi
	done
	local packages=$(
		cat /tmp/progs.csv | sed '/^#/d;/^,/d;s/,.*$//' | tr "\n" " ")

	case $lsb_dist in 
		manjaro | arch)
			yay -S --noconfirm --needed flatpak $packages
	 	;;
		raspbian | ubuntu)
			sudo apt install flatpak $packages
		;;
		fedora)
			dnf install -y flatpak $packages
		*)
			printf $(tput setaf 1)"Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac
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
	git clone -q --depth 1 "$1" "$dir/gitrepo" &&
	cp -rfT "$dir/gitrepo" "/home/$USER/.mozilla/firefox" &&
	return
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
		*)
			echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0)
			return
		;;
		esac
}


agetty_set() {
	local ExexStart="ExecStart=-\/sbin\/agetty --skip-login"
	local log="$ExexStart --login-options $USER --noclear %I \$TERM"
	sed "s/^Exec.*/${log}/" /usr/lib/systemd/system/getty@.service |
		sudo tee /etc/systemd/system/getty@.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl reenable getty@tty1.service
}

virtualbox() {
	# If on V/box, removes v/box from the guest and installs guest-utils.
	# If virtualbox is installed, adds user to vboxusers group
	if [[ $(lspci | grep VirtualBox) ]]; then
		case $lsb_dist in
		arch)
			local g_utils=""
			sudo pacman -S --noconfirm --needed \
				virtualbox-guest-modules-arch virtualbox-guest-utils \
				xf86-video-vmware

			[ ! -f /usr/bin/virtualbox ] && return
			sudo pacman -Rns --noconfirm virtualbox 2>/dev/null
			sudo pacman -Rns --noconfirm \
				virtualbox-host-modules-arch 2>/dev/null
			sudo pacman -Rns --noconfirm virtualbox-guest-iso 2>/dev/null
		;;
		*)
			echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0)
			return
		;;
		esac

	elif [ `command -v virtualbox` ]; then
		sudo gpasswd -a $USER vboxusers >/dev/null 2>&1
	fi
}


it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	# Requires dkms
	local workdir="/home/$USER/.local/sources"
	mkdir -p "$workdir" && cd "$workdir"
	git clone -q https://github.com/bbqlinux/it87
	cd it87 || echo "Failed tio install it87" && return
	sudo make dkms && sudo modprobe it87
	echo "it87" | sudo tee /etc/modules-load.d/it87.conf >/dev/null
}


data() {
	# Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	sudo mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" | 
		sudo tee -a /etc/fstab >/dev/null
}


nvidia_drivers() {
	# Installs proprietery Nvidia drivers for supported distros.
	# Returns with no output, if the installation is in VirutalBox.
	[[ $(lspci | grep VirtualBox) ]] && return

	case $lsb_dist in
	arch)
		pacman -S --noconfirm --needed nvidia nvidia-settings
		if grep -q "^\[multilib\]" /etc/pacman.conf; then
			pacman -S --noconfirm --needed lib32-nvidia-utils
		fi
	;;
	*)
		echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0) 
		return 
	;;
	esac
}


catalog() {
	[ ! -d /home/"$USER"/.local ] && 
	sudo -u "$USER" mkdir /home/"$USER"/.local

	case $lsb_dist in 
		manjaro | arch)
			sudo pacman --noconfirm -Rns $(pacman -Qtdq)
			pacman -Qq > /home/"$USER"/.local/Fresh_pack_list
	 	;;
		raspbian | ubuntu)
			sudo apt-get clean
			sudo apt autoremove
			apt list --installed 2> /dev/null \
				> /home/"$USER"/.local/Fresh_pack_list
		;;
		fedora)
			dnf list installed > /home/"$USER"/.local/Fresh_pack_list
		*)
			printf $(tput setaf 1)"Distro is not supported yet."$(tput sgr0)
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

repo=https://raw.githubusercontent.com/ispanos/anergos/master
programs_repo="$repo/programs/"
package_lists="$@"
lsb_dist="$(. /etc/os-release && echo "$ID")"

printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"


case $lsb_dist in 
    fedora)
        [ -d ~/.local ] && mkdir ~/.local
        dnf list installed > ~/.local/Freshiest
        sudo dnf clean all
        local srtlnk="https://download1.rpmfusion.org"
        local free="free/fedora/rpmfusion-free-release"
        local nonfree="nonfree/fedora/rpmfusion-nonfree-release"
        sudo dnf install -y "$srtlnk/$free-$(rpm -E %fedora).noarch.rpm"
        sudo dnf install -y "$srtlnk/$nonfree-$(rpm -E %fedora).noarch.rpm"
        sudo dnf upgrade -y
        sudo dnf remove -y openssh-server

        sudo dnf copr enable skidnik/i3blocks -y

    ;;
    *)
        pass
    ;;
esac


install_progs "$package_lists"
[ `command -v flatpak` ] &&
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install steam.
# flatpak -y install flathub com.valvesoftware.Steam

[ -f /usr/bin/docker ] && sudo usermod -aG docker $USER
[ -f /etc/libreoffice/sofficerc ] && 
	sudo sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# Configurations are picked according to the hostname of the computer.
case $(hostnamectl | awk -F": " 'NR==1 {print $2}') in 
	killua)
		printf "\n\nkillua:\n"
		it87_driver; data; nvidia_drivers; agetty_set;
		arduino_groups; virtualbox; catalog;
		firefox_configs https://github.com/ispanos/mozzila
		clone_dotfiles https://github.com/ispanos/dotfiles
	;;
	*)
		echo "Unknown hostname"
	;;
esac
