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

	nopasswd_sudo

	local progs_repo=https://raw.githubusercontent.com/ispanos/anergos/main/programs
	install_environment "$@"
	clone_dotfiles git@github.com:ispanos/dotfiles.git
	change_hostname
	#mount_hhd_uuid fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4
	# The following functions are only applied if needed.
	# You may get an error message, but they wont apply any unneeded changes.
	g810_Led_profile
	#it87_driver # don't use
	finalization

	reset_sudo_passwd
}


nopasswd_sudo(){
	# PLEASE USE WITH CARE
	# May cause issues on systems with modified
	# Temporarily disable password to avoid multiple prompts
	mkdir -p /etc/sudoers.d/
	echo "${USER} ALL=(ALL) NOPASSWD: ALL" |
		sudo tee /etc/sudoers.d/anergos >/dev/null
}


reset_sudo_passwd(){
	# Resets sudoers files to the previous state
	sudo rm -rf /etc/sudoers.d/anergos
}


printLists(){
	local list file_loc ID
	[ -z "$ID" ] && ID=$(. /etc/os-release; echo "$ID")
	# Warning: the function assumes you give at least one proper package list.
	[ "$#" -lt 1 ] && echo 1>&2 "${FUNCNAME[0]} - Missing arguments." && exit 1
	# Prints the content of `.csv` files given as arguments.
	# Checks for local files first.

	for list in "$@"; do
		file_loc=(	"programs/$ID.$list.csv"
					"programs/$ID/$list.csv"
					"programs/$file.csv"
					"$ID.$list.csv"
					"$ID/$file.csv"
					"$list.csv"
				)

		# TODO add a suc counter to make sure at least one file is valid
		for location in "${file_loc[@]}"; do
			[ -r "$location" ] && cat "$location" && echo && break
		done
		[ "$?" -ne 0 ] && curl -Ls "$progs_repo/$ID/$list.csv" # suc = true
	done
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


install_environment() {
	local NAME ID packages extra_repos progsFile # nvdri

	ID=$(. /etc/os-release; echo "$ID")
	NAME=$(. /etc/os-release; echo "$NAME")

	progsFile="/tmp/progs_$(date +%s).csv"
	printLists "$@" >>"$progsFile"

	# TODO Better parser
	packages=($(sed '/#.*$/d;/^,/d;s/,.*$//' "$progsFile"))
	extra_repos=($(sed '/^#/d;/^,/d;s/^.*,//' "$progsFile"))

	# Rudimentary check to see if there are any packages in the variable.
	[ -z "$packages" ] && echo 1>&2 "Error parsing package lists." && exit 1

	# Add flatpak to package list
	grep -q "flatpak" <<<"$packages" || [ "$(command -v flatpak)" ] ||
	packages="$packages flatpak"

	[ -d "$HOME/.local" ] || mkdir "$HOME/.local"

	case $ID in
		# arch)
		# 		source archlinux
		# 		arch_ ;;
		fedora) 
				source fedora
				fedora_ ;;
		# pop) 	
		# 		source popos
		# 		pop_ ;;
		*) read -rep "Distro:$NAME is not properly supported yet."; exit 1 ;;
	esac
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
