#!/bin/bash

enable_numlk_tty() {
	cat > /usr/local/bin/numlock <<-EOF
		#!/bin/bash
		# /usr/local/bin/numlock
		# /etc/systemd/system/numlock.service
		for tty in /dev/tty{1..6}
		do
		    /usr/bin/setleds -D +num < "$tty";
		done
	EOF

	cat > /etc/systemd/system/numlock.service <<-EOF
		[Unit]
		Description=numlock
		
		[Service]
		ExecStart=/usr/local/bin/numlock
		StandardInput=tty
		RemainAfterExit=yes
		
		[Install]
		WantedBy=multi-user.target
	EOF

	systemctl enable numlock
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
	sudo -u "$name" yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
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
data
sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 

# cat > /etc/resolv.conf <<-EOF
# 	# Resolver configuration file.
# 	# See resolv.conf(5) for details.
# 	search home
# 	nameserver 192.168.1.1
# EOF