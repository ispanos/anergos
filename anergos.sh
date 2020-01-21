#!/usr/bin/env bash
# License: GNU GPLv3

if [ "$(id -nu)" == "root" ]; then
	cat <<-EOF
		This script changes your users configurations
		and should thus not be run as root.
		You may need to enter your password multiple times.
	EOF
	exit 1
fi

merge_lists() {
	if [ ! "$1" ]; then
		echo 1>&2 "Missing arguments.No programs will be installed."
		return 1
	fi
	# Merges all csv files in one file. Checks for local files first.
	for file in "$@"; do
		if [ -r "$file.csv" ]; then
			cat "$lsb_dist.$file.csv" >>/tmp/progs.csv
		elif [ -r "programs/$file.csv" ]; then
			cat "programs/$lsb_dist.$file.csv" >>/tmp/progs.csv
		else
			curl -Ls "$progs_repo/$lsb_dist.$file.csv" >>/tmp/progs.csv
		fi
	done
}

install_environment() {
	# Depending on the disto, it installs some necessary packages
	# and repositories. This is only tested on Archlinux.
	# Manjaro, Fedora and Ubuntu are not tested, but are here as
	# they could be useful to me in the future.

	local packages extra_repos nvidiaGPU
	packages=$(sed '/^#/d;/^,/d;s/,.*$//' /tmp/progs.csv | tr "\n" " ")
	extra_repos=$(sed '/^#/d;/^,/d;s/^.*,//' /tmp/progs.csv)

	# Installs proprietery Nvidia drivers for supported distros.
	# IF there is an nvidia GPU, it prompts the user to install the drivers.
	nvidiaGPU=$(lspci -k | grep -A 2 -E "(VGA|3D)" | grep "NVIDIA" |
		awk -F'[][]' '{print $2}')
		
	[ "$nvidiaGPU" ] && read -rep "
		Detected Nvidia GPU: $nvidiaGPU
		Would you like to install the non-free Nvidia drivers? [y/N]: " nvdri

	mkdir "$HOME/.local"
	case $lsb_dist in

	manjaro)
		sudo pacman -Syu --noconfirm --needed yay base-devel git
		yay --nodiffmenu --save
		yay -S --noconfirm --needed flatpak $packages

		sudo pacman --noconfirm -Rns $(pacman -Qtdq)
		pacman -Qq >"$HOME/.local/Fresh_pack_list"

		if [ "$(command -v arduino)" ]; then
			echo cdc_acm |
				sudo tee /etc/modules-load.d/cdcacm.conf >/dev/null
			groups | grep -q uucp || sudo usermod -aG uucp "$USER"
			groups | grep -q lock || sudo usermod -aG lock $USER
		fi
		;;

	arch)
		sudo pacman -Syu --noconfirm

		# Installs VirtualBox guest utils only on guests.
		if lspci | grep -q VirtualBox; then
			sudo pacman -S --noconfirm --needed \
				virtualbox-guest-modules-arch virtualbox-guest-utils \
				xf86-video-vmware
		fi

		# Install yay - Aur wrapper.
		git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
		cd /tmp/yay && makepkg -si --noconfirm --needed

		if [[ $nvdri =~ ^[Yy]$ ]]; then
			packages="$packages nvidia nvidia-settings"
			grep -q "^\[multilib\]" /etc/pacman.conf &&
				packages="$packages lib32-nvidia-utils"
		fi

		yay --nodiffmenu --save
		yay -S --noconfirm --needed flatpak $packages

		sudo pacman --noconfirm -Rns $(pacman -Qtdq)
		pacman -Qq >$HOME/.local/Fresh_pack_list

		if [ "$(command -v arduino)" ]; then
			echo cdc_acm |
				sudo tee /etc/modules-load.d/cdcacm.conf >/dev/null
			groups | grep -q uucp || sudo usermod -aG uucp "$USER"
			groups | grep -q lock || sudo usermod -aG lock "$USER"
		fi
		;;

	raspbian | ubuntu)
		sudo apt-get update && sudo apt-get -y upgrade

		for ppa in $extra_repos; do
			sudo add-apt-repository ppa:$ppa -y
		done

		sudo apt install flatpak $packages
		sudo apt-get clean && sudo apt autoremove
		apt list --installed 2>/dev/null >"$HOME/.local/Fresh_pack_list"

		if [ "$(command -v arduino)" ]; then
			groups | grep -q dialout || sudo usermod -aG dialout "$USER"
		fi
		;;

	fedora)
		srtlnk="https://download1.rpmfusion.org"
		free="free/fedora/rpmfusion-free-release"
		nonfree="nonfree/fedora/rpmfusion-nonfree-release"
		sudo dnf install -y "$srtlnk/$free-$(rpm -E %fedora).noarch.rpm"
		sudo dnf install -y "$srtlnk/$nonfree-$(rpm -E %fedora).noarch.rpm"
		sudo dnf upgrade -y
		sudo dnf remove -y openssh-server
		for corp in $extra_repos; do
			sudo dnf copr enable "$corp" -y
		done
		sudo dnf install -y flatpak $packages
		dnf list installed >"$HOME/.local/Fresh_pack_list"
		;;

	*) printf "/n/n/n UNSUPPORTED DISTRO\n\n\n" && exit ;;

	esac

	sudo flatpak remote-add --if-not-exists \
		flathub https://flathub.org/repo/flathub.flatpakrepo
	# flatpak -y install flathub com.valvesoftware.Steam

	[ "$(command -v virtualbox)" ] && sudo usermod -aG vboxusers "$USER"
	[ "$(command -v docker)" ] && sudo usermod -aG docker "$USER"

	printf "All programs have been installed...\n\n\n"
	sleep 2
}

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
	local dir
	dotfilesrepo=$1

	dir=$(mktemp -d)
	sudo chown -R "$USER" "$dir"
	echo ".cfg" >"$dir/.gitignore"
	git clone -q --bare "$dotfilesrepo" "$dir/.cfg"
	git --git-dir="$dir/.cfg/" --work-tree="$dir" checkout
	git --git-dir="$dir/.cfg/" --work-tree="$dir" config \
		--local status.showUntrackedFiles no
	rm "$dir/.gitignore"
	cp -rfT "$dir/" "$HOME/"
}

firefox_configs() {
	# Downloads firefox configs. Requires config repo.
	[ "$1" ] || return
	local dir
	mkdir -p "$HOME/.mozilla/firefox"
	sudo chown -R "$USER" "$HOME/.mozilla/firefox"
	dir=$(mktemp -d)
	sudo chown -R "$USER" "$dir"
	printf "\n\n\n\nCloning Firefox configs.\n"
	git clone -q --depth 1 "$1" "$dir/gitrepo" &&
		cp -rfT "$dir/gitrepo" "$HOME/.mozilla/firefox" && return
	echo "firefox_configs failed."
}

agetty_set() { # I don't use a display manager.
	# This auto-completes the username ( $USER ) for faster logins on tty1.
	local ExexStart log
	ExexStart="ExecStart=-\/sbin\/agetty --skip-login --login-options"
	log="$ExexStart $USER --noclear %I \$TERM"
	sed "s/^Exec.*/$log/" /usr/lib/systemd/system/getty@.service |
		sudo tee /etc/systemd/system/getty@.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl reenable getty@tty1.service
}

it87_driver() { # Requires dkms
	# Installs driver for many Ryzen's motherboards temperature sensors
	local workdir
	workdir=$HOME/.local/sources
	mkdir -p "$workdir" && cd "$workdir" || return
	git clone -q https://github.com/bbqlinux/it87 &&
		cd it87 && sudo make dkms && sudo modprobe it87 &&
		echo "it87" | sudo tee /etc/modules-load.d/it87.conf >/dev/null
}

data() { # Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD,
	# or help me improve mine.
	sudo mkdir -p /media/Data
	local duuid mntPoint mntOpt
	duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	mntPoint="/media/Data"
	mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n%s \t%s \t%s\t\\n" "$duuid" "$mntPoint" "$mntOpt" |
		sudo tee -a /etc/fstab >/dev/null
}

g810_driver(){
	yay -S --noconfirm --needed g810-led-git
	cat <<-EOF | sudo tee /etc/g810-led/profile >/dev/null
		# Sample profile by groups keys
		g logo B3B383
		g indicators ffffff
		g multimedia B3B383
		g fkeys B3B383
		g modifiers B3B383
		g arrows B3B383
		g numeric B3B383
		g functions B3B383
		g keys B3B383
		g gkeys B3B383

		# Defaults
		#g logo 000096
		#g indicators ffffff
		#g multimedia 009600
		#g fkeys ff00ff
		#g modifiers ff0000
		#g arrows ffff00
		#g numeric 00ffff
		#g functions ffffff
		#g keys 009696
		#g gkeys ffffff

		c # Commit changes
	EOF
}

lsb_dist="$(source /etc/os-release && echo "$ID")"
printf "%sAnergos:\nDistribution - %s\n\n%s" $(tput setaf 4) $lsb_dist $(tput sgr0)
# echo  -e "\e[0;36mDone.\e[39m"
progs_repo=https://raw.githubusercontent.com/ispanos/anergos/master/programs
merge_lists $@ && install_environment

case $(hostnamectl | awk -F": " 'NR==1 {print $2}') in
killua)
	printf "\n\nkillua:\n"
	it87_driver
	data
	agetty_set
	g810_driver
	# for lol
	#echo "abi.vsyscall32 = 0" | sudo tee /etc/sysctl.conf >/dev/null
	;;
*) echo "Unknown hostname" ;;
esac

clone_dotfiles https://github.com/ispanos/dotfiles
firefox_configs https://github.com/ispanos/mozzila

echo "Anergos installation is complete. Please log out and log back in."
