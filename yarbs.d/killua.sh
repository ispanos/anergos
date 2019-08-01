#!/bin/bash

enable_numlk_tty() {
	dialog  --infobox "Installing systemd-numlockontty." 3 40
	sudo -u "$name" yay -S --noconfirm systemd-numlockontty >/dev/null 2>&1
	serviceinit numLockOnTty
}

temps() {
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

resolv_conf() {
	cat > /etc/resolv.conf <<-EOF
		# Resolver configuration file.
		# See resolv.conf(5) for details.
		search home
		nameserver 192.168.1.1
	EOF
}

sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 
enable_numlk_tty
temps
data
resolv_conf
