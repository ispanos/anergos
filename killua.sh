#!/bin/bash

enable_numlk_tty() {
	dialog  --infobox "Installing systemd-numlockontty." 3 40
	sudo -u yiannis yay -S --noconfirm systemd-numlockontty >/dev/null 2>&1 &&
	systemctl enable numLockOnTty
}

lock_sleep() {
	if [ -f /usr/bin/i3lock ] && [ ! -f /usr/bin/swaylock ]; then
		cat > /etc/systemd/system/SleepLocki3@yiannis.service <<-EOF
			#/etc/systemd/system/
			[Unit]
			Description=Turning i3lock on before sleep
			Before=sleep.target
			
			[Service]
			User=%I
			Type=forking
			Environment=DISPLAY=:0
			ExecStart=/usr/bin/i3lock -e -f -c 000000 -i /home/yiannis/.config/wall.png -t
			ExecStartPost=/usr/bin/sleep 1
			
			[Install]
			WantedBy=sleep.target
		EOF
	fi
	systemctl enable SleepLocki3@yiannis
}

temps() {
	# Install driver for Asus X370 Prime pro fan/thermal sensors
	dialog  --infobox "Installing it87-dkms-git." 3 40
	sudo -u yiannis yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
	echo "it87" > /etc/modules-load.d/it87.conf
}


data() {
	cat >> /etc/fstab <<-EOF
		# /dev/sda1 LABEL=data
		UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4  /media/Data    ext4 rw,noatime,nofail,user,auto    0  2
	EOF
}

enable_numlk_tty
lock_sleep
temps
#data
sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 

# cat > /etc/resolv.conf <<-EOF
# 	# Resolver configuration file.
# 	# See resolv.conf(5) for details.
# 	search home
# 	nameserver 192.168.1.1
# EOF
