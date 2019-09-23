#!/usr/bin/env bash
# License: GNU GPLv3
# /*
# bootloader | objcopy | Preparing kernels for /EFI/Linux
# */

[ $1 ] || { 1>&2 echo "No arguments passed. Please read the scripts description." && exit;}

repo=https://raw.githubusercontent.com/ispanos/anergos/master
hostname=killua
name=yiannis
user_password=
root_password=
multi_lib_bool=
timezone=
lang=
dotfilesrepo=
moz_repo=

function get_variables() { 
	if [ -z "$hostname" ]; then
		hostname=$(dialog --inputbox "Please enter the hostname." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
		automated=false
	fi

	[ -z "$name" ] && name=$(dialog --inputbox "Please enter a name for a user account." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Name not valid. Start with a letter, use lowercase letters, - or _" 10 60 3>&1 1>&2 2>&3 3>&1)
		automated=false
	done

	if [ -z "$user_password" ]; then
		user_password=$(dialog --no-cancel --passwordbox "Enter a password for $name." 10 60 3>&1 1>&2 2>&3 3>&1)
		pwd=$(dialog --no-cancel --passwordbox "Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)
		while ! [ "$user_password" = "$pwd" ]; do unset pwd
			user_password=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)
			pwd=$(dialog --no-cancel --passwordbox "Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done
		unset pwd && automated=false
	fi

	if [ -z "$root_password" ]; then 
		root_password=$(dialog --no-cancel --passwordbox "Enter root user's password." 10 60 3>&1 1>&2 2>&3 3>&1)
		pwd=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		while ! [ "$root_password" = "$pwd" ]; do unset pwd
			root_password=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
			pwd=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done
		unset pwd && automated=false
	fi
	
	[ "$automated" = "false" ] && dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35 || exit
}

clear

if [ ! -f /usr/bin/dialog ]; then
	printf "Installing dialog, to make things look better...\n"
	pacman --noconfirm -Syyu dialog >/dev/null 2>&1
fi

get_variables
clear
curl -sL "$repo/anergos.d/arch.sh" 	> /tmp/arch.sh && source /tmp/arch.sh
curl -sL "$repo/anergos.d/mpc.sh" 	> /tmp/mpc.sh  && source /tmp/mpc.sh
exit
