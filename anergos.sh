#!/usr/bin/env bash
# Copyright (C) 2020 Ioannis Spanos

# License: GNU GPLv3
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#set -x

main(){
	if [ "$(id -nu)" == "root" ]; then
		cat <<-EOF
			This script changes your users configurations
			and should thus not be run as root.
			You may need to enter your password multiple times.
		EOF
		exit
	fi

	local progs_repo
	progs_repo=https://raw.githubusercontent.com/ispanos/anergos/master/programs
	install_environment "$@"
	clone_dotfiles git@github.com:ispanos/dotfiles.git
	# The following functions are only applied if needed.
	# You may get an error message, but they wont apply any unneeded changes.
	g810_Led_profile
	#it87_driver
	#mount_hhd_uuid fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4
	finalization
}

printLists(){
	local list file_loc i ID
	[ -z "$ID" ] && ID=$(. /etc/os-release; echo "$ID")
	# Warning: the function assumes you give at least one proper package list.
	[ "$#" -lt 1 ] && echo 1>&2 "${FUNCNAME[0]} - Missing arguments." && exit 1
	# Prints the content of `.csv` files given as arguments.
	# Checks for local files first.
	file_loc=(	"programs/$ID.$list.csv"
				"programs/$ID/$list.csv"
				"programs/$file.csv"
				"$ID.$list.csv"
				"$ID/$file.csv"
				"$list.csv"
			)

	for list in "$@"; do
		for i in "${!file_loc[@]}"; do
			[ -r "${file_loc[$i]}" ] && cat "${file_loc[$i]}" && echo && break
		done
		[ "$?" -ne 0 ] && curl -Ls "$progs_repo/$ID/$list.csv"
		# ^--^ SC2181: Check exit code directly with e.g. 'if mycmd;', not indirectly with $?.
	done
}

nvidia_check(){
    local nvidiaGPU nvdri
	# Installs proprietery Nvidia drivers for supported distros.
	# If there is an nvidia GPU, it asks the user to install drivers.
	[ "$(command -v lspci)" ] &&
	nvidiaGPU=$(lspci -k | grep -A 2 -E "(VGA|3D)" | grep "NVIDIA" |
				awk -F'[][]' '{print $2}')

	[ "$nvidiaGPU" ] && read -rep "
		Detected Nvidia GPU: $nvidiaGPU
		Install proprietary Nvidia drivers? [y/N]: " nvdri
    echo nvdri
}

change_hostname(){
	local ans1 hostname
	echo "Current hostname is $(hostname)"
	read -rep 'Would you like to change it? [Y/n]: ' ans1
	[[ $ans1 =~ ^[Yy]$ ]] && read -rep 'New hostname: ' hostname
	sudo hostnamectl set-hostname "$hostname"

	{
	cat <<-EOF
		#<ip-address>  <hostname.domain.org>    <hostname>
		127.0.0.1      localhost
		::1            localhost
		127.0.1.1      ${hostname}.localdomain  $hostname
	EOF
	} | sudo tee /etc/hosts >/dev/null
}

arch_(){
	echo "Updating and installing git if needed."
	sudo reflector --verbose \
				   --latest 5 \
				   --sort rate --save /etc/pacman.d/mirrorlist
	sudo pacman -Syu --noconfirm --needed git

	if [ ! "$(command -v yay)" ]; then
		git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
		cd /tmp/yay && makepkg -si --noconfirm --needed
	fi

	# # Installs VirtualBox guest utils only on guests.
	# if lspci | grep -q VirtualBox; then
	# 	packages="$packages virtualbox-guest-utils xf86-video-vmware"
	# fi

	if [[ $nvdri =~ ^[Yy]$ ]]; then
		packages="$packages nvidia nvidia-settings"
		grep -q "^\[multilib\]" /etc/pacman.conf &&
			packages="$packages lib32-nvidia-utils"
	fi

	yay --nodiffmenu --needed --removemake --save
	yay -S --noconfirm --needed --removemake $packages || exit 3

	[ -f  "$HOME"/.local/Fresh_pack_list ] ||
		yay -Qq >"$HOME"/.local/Fresh_pack_list

	if [ "$(command -v arduino)" ]; then
		sudo usermod -aG uucp "$USER"
		sudo usermod -aG lock "$USER"
		echo cdc_acm |
			sudo tee /etc/modules-load.d/cdcacm.conf >/dev/null
	fi
}

manjaro_(){
	sudo pacman -Syu --noconfirm --needed yay base-devel git

	# To do: Install VirtualBox guest utils only on guests.
	# To do: Install Nvidia drivers
	yay --nodiffmenu --save
	yay -S --noconfirm --needed --removemake $packages
	yay -Yc --noconfirm
	[ -f  "$HOME"/.local/Fresh_pack_list ] ||
		yay -Qq >"$HOME"/.local/Fresh_pack_list
}

pop_(){
	lspci -k | grep -q "QEMU Virtual Machine" &&
	packages="$packages qemu-guest-agent"

	change_hostname

	for ppa in $extra_repos; do
		sudo add-apt-repository ppa:"$ppa" -y
	done

	sudo apt-get update && sudo apt-get -y upgrade
	sudo apt-get install $packages -y
	[[ "$?" -eq 100 ]] && echo 1>&2 "Wrong package name." && exit 100
	sudo apt-get clean && sudo apt autoremove

	[ "$(command -v pip3)" ] || sudo apt-get install python3-pip -y
	pip3 install ansible ansible-lint --user

	if [ "$(command -v sway)" ] || [ "$(command -v i3)" ]; then
		pip3 install i3ipc --user
		curl -Ls \
			"https://raw.githubusercontent.com/nwg-piotr/autotiling/master/autotiling.py" \
			>~/.local/bin/wm-scripts/autotiling
		chmod +x ~/.local/bin/wm-scripts/autotiling
		install_xkb-switch
	fi

	chsh -s /bin/usr/zsh
	[ -f  "$HOME"/.local/Fresh_pack_list ] ||
		apt list --installed 2>/dev/null >"$HOME/.local/Fresh_pack_list"

	if [ "$(command -v arduino)" ]; then
		sudo usermod -aG dialout "$USER"
	fi
}

fedora_(){

	# -- paprefs needs pipewire alternative
	# Vscode

	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
	sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'

	dnf check-update
	sudo dnf install -y code

	# R
	sudo dnf install -y 'dnf-command(copr)'
	sudo dnf copr -y enable iucar/cran
	sudo dnf install -y R-CoprManager

	srtlnk="https://download1.rpmfusion.org"
	free="free/fedora/rpmfusion-free-release"
	nonfree="nonfree/fedora/rpmfusion-nonfree-release"
	sudo dnf install -y "$srtlnk/$free-$(rpm -E %fedora).noarch.rpm"
	sudo dnf install -y "$srtlnk/$nonfree-$(rpm -E %fedora).noarch.rpm"
	sudo dnf upgrade -y

	change_hostname

	# Install Third Party Repositories.
	sudo dnf install fedora-workstation-repositories
	# Enable the Google Chrome repo:
	sudo dnf config-manager --set-enabled google-chrome
	sudo dnf install -y google-chrome-stable

	# To do: Install VirtualBox guest utils only on guests.
	# To do: Install Nvidia drivers ?

	for corp in $extra_repos; do
		sudo dnf copr enable "$corp" -y
	done

	# TODO change to array
	sudo dnf install -y $packages

	[ -f  "$HOME"/.local/Fresh_pack_list ] ||
		dnf list installed >"$HOME/.local/Fresh_pack_list"

	sudo flatpak remote-add --if-not-exists flathub \
	https://flathub.org/repo/flathub.flatpakrepo


	flatpaks=(
		com.dropbox.Client
		com.microsoft.Teams
		com.mattermost.Desktop
		us.zoom.Zoom
		com.discordapp.Discord
		org.gnome.gitlab.YaLTeR.VideoTrimmer
		nl.hjdskes.gcolor3
		com.stremio.Stremio
		io.dbeaver.DBeaverCommunity
		io.dbeaver.DBeaverCommunity.Client.mariadb
		org.gimp.GIMP
		org.audacityteam.Audacity
		com.github.xournalpp.xournalpp
		com.spotify.Client
		org.octave.Octave
		com.skype.Client
		com.ulduzsoft.Birdtray
		org.mozilla.Thunderbird
		com.skype.Client
	)
	# com.jetbrains.PyCharm-Community

	sudo flatpak install -y "${flatpaks[@]}"

	# Codecs
	sudo dnf install gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel
	sudo dnf install lame\* --exclude=lame-devel
	sudo dnf group upgrade --with-optional Multimedia

	# G810
	sudo dnf copr enable lkiesow/g810-led
	sudo dnf install g810-led

	# Virtualization
	sudo dnf install @virtualization
	# sudo sed -i '/#unix_sock_group = "libvirt"/s/^#//' /etc/libvirt/libvirtd.conf
	sudo usermod -a -G libvirt "$(whoami)"

	# REMOVE
	sudo dnf remove -y gnome-tour gnome-photos gnome-maps gnome-help

	# Teamviewer
	# wget -q "https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm"
	# sudo teamviewer –daemon disable

	chsh $USER -s /usr/bin/zsh
}

install_environment() {
	local NAME ID packages extra_repos nvdri progsFile

	ID=$(. /etc/os-release; echo "$ID")
	NAME=$(. /etc/os-release; echo "$NAME")

	progsFile="/tmp/progs_$(date +%s).csv"
	printLists "$@" >>"$progsFile"
	packages=$(sed '/#.*$/d;/^,/d;s/,.*$//' "$progsFile")
	extra_repos=$(sed '/^#/d;/^,/d;s/^.*,//' "$progsFile") # Fix with awk. ?

	# Rudimentary check to see if there are any packages in the variable.
	[ -z "$packages" ] && echo 1>&2 "Error parsing package lists." && exit 1

	grep -q "flatpak" <<<"$packages" || [ "$(command -v flatpak)" ] ||
	packages="$packages flatpak"

	[ -d "$HOME/.local" ] || mkdir "$HOME/.local"

	case $ID in
		arch) 	nvdri=$(nvidia_check)
				arch_ ;;
		fedora) fedora_ ;;
		# manjaro) manjaro_ ;;
		pop|ubuntu) pop_ ;;
		*) read -rep "Distro:$NAME is not properly supported yet."; exit 1 ;;
	esac
}

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	if [ ! "$(command -v git)" ]; then
		echo 1>&2 "${FUNCNAME[0]} requires git. Skipping."
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

	ln -s .profile .zprofile
}

it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	if [ ! "$(command -v git)" ] || [ ! "$(command -v dkms)" ]; then
		echo 1>&2 "${FUNCNAME[0]} requires git and dkms. Skipping."
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
		echo 1>&2 "Automated test for ${FUNCNAME[0]} requires lm_sensors."
		echo "If you know that you need the driver, type either 'Y' or 'y'"
		read -rep "to install it. [y/N]:" needed
	fi

	[[ $needed =~ ^[Yy]$ ]] || return

	workdir=$HOME/.local/share/build_sources
	[ -d "$workdir" ] || mkdir -p "$workdir" && cd "$workdir" || return 2
	git clone -q https://github.com/bbqlinux/it87 &&
		cd it87 && sudo make dkms && sudo modprobe it87 &&
		echo "it87" | sudo tee /etc/modules-load.d/it87.conf >/dev/null
}

install_xkb-switch() {
	# Pop!_os / Ubuntu
	[ "$(command -v xkb-switch)" ] && return 0
	# Installs xkb-switch, needed for i3blocks keyboard layout module.
	if [ ! "$(command -v git)" ] || [ ! "$(command -v cmake)" ]; then
		echo 1>&2 "${FUNCNAME[0]} requires git and cmake. Skipping."
		return 1
	fi

	local workdir

	workdir=$HOME/.local/share/build_sources

	[ -d "$workdir" ] || mkdir -p "$workdir" && cd "$workdir" || return 2
	git clone -q https://github.com/grwlf/xkb-switch.git &&
		cd xkb-switch && mkdir build && cd build && cmake .. && make &&
        sudo make install && sudo ldconfig || return 7
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
	[ -z "$label" ] && [ "$(wc -w <<< "$label")" -ne 1 ] &&
		echo 1>&2 "UUID doesn't correspond to a label" &&
		return 6

	[ -d "/media/$label" ] || sudo mkdir -p "/media/$label"
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

finalization(){
	[ "$(command -v sway)" ] &&
	sudo sed -i 's/^Exec=sway$/Exec=\/bin\/zsh -l -c sway/' \
		/usr/share/wayland-sessions/sway.desktop

	# Also for Fedora
	sudo systemctl enable --now libvirtd &&
		sudo usermod -aG libvirt "$USER"

	sudo flatpak remote-add --if-not-exists flathub  --system \
		https://flathub.org/repo/flathub.flatpakrepo
	# flatpak remote-add --if-not-exists flathub --user \
	# 	https://flathub.org/repo/flathub.flatpakrepo

	# pip install i3ipc # Add for non-arch distros.

	# for printers? why?
	# sudo usermod -aG lp "$USER"
	# [ "$(command -v virtualbox)" ] && sudo usermod -aG vboxusers "$USER"
	# [ "$(command -v docker)" ] && sudo usermod -aG docker "$USER"
}

# todo
# https://stackoverflow.com/questions/35773299/how-can-you-export-the-visual-studio-code-extension-list

main "$@"
