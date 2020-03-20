#!/usr/bin/env bash
# License: GNU GPLv3

install_environment() {
	# Depending on the disto, it installs some necessary packages
	# and repositories. This is only tested on Archlinux.
	# Manjaro, Fedora and Ubuntu are not tested, but are here as
	# they could be useful to me in the future.

	# Warning:
	# The script assumes you give at least one proper package list.
	if [ "$#" -lt 1 ]; then
		echo 1>&2 "Missing arguments."
		exit 1
	fi

	local packages extra_repos nvidiaGPU

	# Merges all csv files in one file. Checks for local files first.
	for file in "$@"; do
		if [ -r "$ID.$file.csv" ]; then
			cat "$ID.$file.csv" >>/tmp/progs.csv
		elif [ -r "programs/$ID.$file.csv" ]; then
			cat "programs/$ID.$file.csv" >>/tmp/progs.csv
		else
			curl -Ls "$progs_repo/$ID.$file.csv" >>/tmp/progs.csv
		fi
	done

	packages=$(sed '/^#/d;/^,/d;s/,.*$//' /tmp/progs.csv)
	extra_repos=$(sed '/^#/d;/^,/d;s/^.*,//' /tmp/progs.csv)

	# Basic check to see if there any packages in the variable.
	if [ -z "$packages" ]; then
		echo 1>&2 "Error parsing package lists."
		exit 1
	fi

	# Installs proprietery Nvidia drivers for supported distros.
	# IF there is an nvidia GPU, it prompts the user to install the drivers.
	nvidiaGPU=$(lspci -k | grep -A 2 -E "(VGA|3D)" | grep "NVIDIA" |
		awk -F'[][]' '{print $2}')

	[ "$nvidiaGPU" ] && read -rep "
		Detected Nvidia GPU: $nvidiaGPU
		Would you like to install the non-free Nvidia drivers? [y/N]: " nvdri

	mkdir "$HOME/.local"

	case $ID in

	arch)
		echo "Updating and installing git and base-devel if needed."
		sudo pacman -Syu --noconfirm --needed git base-devel

		if [ ! "$(command -v yay)" ]; then
			git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
			cd /tmp/yay && makepkg -si --noconfirm --needed
		fi

		# Installs VirtualBox guest utils only on guests.
		if lspci | grep -q VirtualBox; then
			packages="$packages virtualbox-guest-modules-arch 
			virtualbox-guest-utils xf86-video-vmware"
		fi

		if [[ $nvdri =~ ^[Yy]$ ]]; then
			packages="$packages nvidia nvidia-settings"
			grep -q "^\[multilib\]" /etc/pacman.conf &&
				packages="$packages lib32-nvidia-utils"
		fi

		yay --nodiffmenu --save
		yay -S --noconfirm --needed $packages
		yay -Yc --noconfirm
		yay -Qq >$HOME/.local/Fresh_pack_list

		if [ "$(command -v arduino)" ]; then
			echo cdc_acm |
				sudo tee /etc/modules-load.d/cdcacm.conf >/dev/null
			groups | grep -q uucp || sudo usermod -aG uucp "$USER"
			groups | grep -q lock || sudo usermod -aG lock "$USER"
		fi
		;;

	manjaro)
		sudo pacman -Syu --noconfirm --needed yay base-devel git

		# Installs VirtualBox guest utils only on guests.
			#TODO
		# Install Nvidia drivers
			#TODO
		yay --nodiffmenu --save
		yay -S --noconfirm --needed $packages
		yay -Yc --noconfirm
		yay -Qq >"$HOME/.local/Fresh_pack_list"

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

		# Installs VirtualBox guest utils only on guests.
			#TODO

		sudo apt install $packages
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

		# Installs VirtualBox guest utils only on guests.
			#TODO

		for corp in $extra_repos; do
			sudo dnf copr enable "$corp" -y
		done
		sudo dnf install -y $packages
		dnf list installed >"$HOME/.local/Fresh_pack_list"
		;;

	*) printf "/n/n/n UNSUPPORTED DISTRO\n\n\n" && exit 1;;

	esac
	[ "$(command -v flatpak)" ] && sudo flatpak remote-add --if-not-exists \
						flathub https://flathub.org/repo/flathub.flatpakrepo
	# flatpak -y install flathub com.valvesoftware.Steam`

	[ "$(command -v virtualbox)" ] && sudo usermod -aG vboxusers "$USER"
	[ "$(command -v docker)" ] && sudo usermod -aG docker "$USER"

	printf "All programs have been installed...\n\n\n"
	sleep 2
}

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	if [ ! "$(command -v git)" ]; then
		echo "${FUNCNAME[0]} requires git. Skipping."
		return 1
	fi

	[ -z "$1" ] && return 1
	local dir dotfilesrepo
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

agetty_set() {
	# Doesn't ask for username on the tty for faster logins.
	# Default user is going to be the user who's running the script.

	local ExexStart log
	ExexStart="ExecStart=-\/sbin\/agetty --skip-login --login-options"
	log="$ExexStart $USER --noclear %I \$TERM"
	sed "s/^Exec.*/$log/" /usr/lib/systemd/system/getty@.service |
		sudo tee /etc/systemd/system/getty@.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl reenable getty@tty1.service

	grep -q "Anergos" /etc/issue && return
	# Edits login screen
	cat <<-EOF | sudo tee -a /etc/issue >/dev/null
		\e[0;36m
		 Anergos Meta-distribution
		 Website:  github.com/ispanos/anergos
		 Hostname: \\n
		\e[0m
	EOF
}

it87_driver() {
	modprobe -R it87 >/dev/null && return
	# Installs driver for many Ryzen's motherboards temperature sensors
	if [ ! "$(command -v git)" ] || [ ! "$(command -v dkms)" ]; then
		echo "${FUNCNAME[0]} requires git and dkms. Skipping."
		return 1
	fi

	local needed workdir sensors_out chip ioSensors
	# Check to see if it87 driver is needed.
	if [ "$(command -v sensors-detect)" ]; then
		read -r -d '' ioSensors <<-EOF
			IT8603E IT8623E IT8620E IT8622E IT8625E IT8665E IT8705F IT8712F
			IT8716F IT8726F IT8720F IT8721F IT8758E IT8728F IT8732F IT8771E
			IT8772E IT8781F IT8782F IT8783E IT8783F IT8790E SiS950
		EOF

		sensors_out=$(sudo sensors-detect --auto)

		for chip in $ioSensors; do
			if grep -q "$chip" <<< "$sensors_out"; then
				needed=Y
				break
			fi
		done
	else
		echo "Automated test for ${FUNCNAME[0]} requires lm_sensors."
		echo "If you know that you need the driver, type either 'Y' or 'y'"
		read -rep "to install it. [y/N]:" needed
	fi

	[[ $needed =~ ^[Yy]$ ]] || return

	workdir=$HOME/.local/sources
	mkdir -p "$workdir" && cd "$workdir" || return 2
	git clone -q https://github.com/bbqlinux/it87 &&
		cd it87 && sudo make dkms && sudo modprobe it87 &&
		echo "it87" | sudo tee /etc/modules-load.d/it87.conf >/dev/null
}

mount_hhd_uuid() {
    # Mounts my HHD, provided the UUID, at /media/foo,
    # where "foo" is the label of the drive.

	# Makes sure there is only 1 argument.
    [ "$#" -ne 1 ] && echo 1>&2 "Invalid UUID" && return 6
	# Makes sure the UUID isn't already in fstab.
	grep -q "$1" /etc/fstab && return

	local label mntOpt
	label=$(sudo blkid -o list | grep "$1" | awk '{print $3}')
	# Makes sure the partition has a label.
	[ -z "$label" ] && [ "$(wc -w <<< $label)" -ne 1 ] &&
		echo 1>&2 "UUID doesn't correspond to a label" &&
		return 6

    sudo mkdir -p "/media/$label"
	mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n%s \t%s \t%s\t\\n" "UUID=$1" "/media/$label" "$mntOpt" |
		sudo tee -a /etc/fstab >/dev/null
}

g810_Led_profile(){
	# https://github.com/MatMoul/g810-led/
	[ -d /etc/g810-led ] || return 5
	sudo mv /etc/g810-led/profile /etc/g810-led/old_profile
	cat <<-EOF | sudo tee /etc/g810-led/profile >/dev/null
		a 856054
		k logo 000030
		k win_left 000030
		k win_right 000030
		k game_mode ff0000
		k caps_indicator ff0000
		k scrolllock 000000
		k num_indicator ffffff
		k light 505050
		g arrows 000030
		c
	EOF
}

if [ "$(id -nu)" == "root" ]; then
	cat <<-EOF
		This script changes your users configurations
		and should thus not be run as root.
		You may need to enter your password multiple times.
	EOF
	exit
fi

source /etc/os-release
progs_repo=https://raw.githubusercontent.com/ispanos/anergos/master/programs

printf "Anergos:\nDistribution -\e[%sm %s \e[0m\n\n" $ANSI_COLOR $ID
install_environment "$@"
clone_dotfiles https://github.com/ispanos/dotfiles
agetty_set

# The following functions are only applied if needed.
# You may get an error message, but they wont apply any unneeded changes.
g810_Led_profile
it87_driver
mount_hhd_uuid fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4

echo "Anergos installation is complete. Please log out and log back in."
