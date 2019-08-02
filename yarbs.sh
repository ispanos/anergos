#!/bin/bash
# License: GNU GPLv3

function error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

timezone="Europe/Athens"
lang="en_US.UTF-8"

repo=https://raw.githubusercontent.com/ispanos/YARBS/master

i3="$repo/programs/i3.csv"
coreprogs="$repo/programs/progs.csv"
common="$repo/programs/common.csv"
sway="$repo/programs/sway.csv"
gnome="$repo/programs/gnome.csv"

function help() {
	cat <<-EOF
		Multilib: -m             Enable multilib.
		Dotfiles: -d <link>      to set your own dotfiles's repo. By default it uses my own dotfiles repository.
		Packages: -p             Add your own link(s) with the list(s) of packages you want to install. -- Overides defaults.

		Example: yarbs -p link1 link2 file1 -m -d https://yourgitrepo123.xyz/dotfiles
		Visit the original repo https://github.com/ispanos/yarbs.git for more info.
	EOF
}

while getopts "mhd:p:" option; do
	case "${option}" in
		m) multi_lib_bool="true" ;;
		d) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
		p) prog_files=${OPTARG} ;;
		h) help && exit ;;
		*) help && exit  ;;
	esac
done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/ispanos/dotfiles.git"
[ -z "$prog_files" ] && prog_files="$i3 $coreprogs $common"

function serviceinit() {
	for service in "$@"; do
		dialog --infobox "Enabling \"$service\"..." 4 40
		systemctl enable "$service"  > /dev/null 2>&1
	done
}

function newperms() {
	echo "$* " > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

[ -r autoconf.sh ] && source autoconf.sh

curl -sL "$repo/yarbs.d/dialog_inputs.sh" > /tmp/dialog_inputs.sh && source /tmp/dialog_inputs.sh

curl -sL "$repo/yarbs.d/arch.sh" > /tmp/arch.sh && source /tmp/arch.sh

curl -sL "$repo/yarbs.d/mpc.sh" > /tmp/mpc.sh && source /tmp/mpc.sh

newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: \
/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart NetworkManager,\
/usr/bin/systemctl restart systemd-networkd,\
/usr/bin/systemctl restart systemd-resolved"

#####
##
## it87
##
####