#!/bin/bash

function get_dialog() {
	echo "Installing dialog, to make things look better..."
	pacman --noconfirm -Syyu dialog >/dev/null 2>&1
}

function get_hostname() { 
	if [ -z "$hostname" ]; then
		hostname=$(dialog --inputbox "Please enter the hostname." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
		automated=false
	fi
}

function get_userandpass() {
	if [ -z "$name" ]; then 
		name=$(dialog --inputbox "Please enter a name for a user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
	fi

	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Name not valid. Start with a letter, use lowercase letters, - or _" 10 60 3>&1 1>&2 2>&3 3>&1)
	done

	if [ -z "$user_password" ]; then
		upwd1=$(dialog --no-cancel --passwordbox "Enter a password for $name." 10 60 3>&1 1>&2 2>&3 3>&1)
		upwd2=$(dialog --no-cancel --passwordbox "Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)

		while ! [ "$upwd1" = "$upwd2" ]; do
			unset upwd2
			upwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)
			upwd2=$(dialog --no-cancel --passwordbox "Retype ${name}'s password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done

		automated=false

	else
		upwd1=$user_password
		upwd2=$user_password
	fi
}

function get_root_pass() {
	if [ -z "$root_password" ]; then 
		rpwd1=$(dialog --no-cancel --passwordbox "Enter root user's password." 10 60 3>&1 1>&2 2>&3 3>&1)
		rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)

		while ! [ "$rpwd1" = "$rpwd2" ]; do
			unset rpwd2
			rpwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
			rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done
	
		automated=false
	else
		rpwd1=$root_password
		rpwd2=$root_password
	fi
}

function get_inputs() {
	get_dialog
	get_hostname
	get_userandpass
	get_root_pass
	if [ "$automated" = "false" ]; then
		dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35
	fi
}