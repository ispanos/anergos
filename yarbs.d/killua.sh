#!/bin/bash

enable_numlk_tty() {
	cat > /etc/systemd/system/numLockOnTty.service <<-EOF
		[Unit]
		Description=numlockOnTty
		
		[Service]
		ExecStart=/usr/bin/numlockOnTty
		
		[Install]
		WantedBy=multi-user.target
	EOF

	cat > /usr/bin/numlockOnTty <<-EOF
		#!/bin/bash
		for tty in /dev/tty{1..6}
		do
		    /usr/bin/setleds -D +num < "$tty";
		done
	EOF

	chmod +x /usr/bin/numlockOnTty
	serviceinit numLockOnTty
}

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

resolv_conf() {
	cat > /etc/resolv.conf <<-EOF
		# Resolver configuration file.
		# See resolv.conf(5) for details.
		search home
		nameserver 192.168.1.1
	EOF
}