#!/bin/bash

temps() {
	# Change installation method!!
	# https://aur.archlinux.org/packages/it87-dkms-git/
	# https://github.com/bbqlinux/it87

	# Install driver for Asus X370 Prime pro fan/thermal sensors
	dialog  --infobox "Installing it87-dkms-git." 3 40
	sudo -u "$name" yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
	echo "it87" > /etc/modules-load.d/it87.conf
}

data() {
	mkdir -p /media/Data
	cat >> /etc/fstab <<-EOF
		# /dev/sda1 LABEL=data
		UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4  /media/Data    ext4 rw,noatime,nofail,user,auto    0  2
	EOF
}

temps
data

enable_numlk_tty
resolv_conf