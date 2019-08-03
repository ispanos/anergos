#!/bin/bash

function power_is_suspend() { sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf;}

function enable_numlk_tty() {
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
	systemctl enable numLockOnTty
}

resolv_conf() {
	cat > /etc/resolv.conf <<-EOF
		# Resolver configuration file.
		# See resolv.conf(5) for details.
		search home
		nameserver 192.168.1.1
	EOF
}

function create_swapfile() {
	dialog --infobox "Creating swapfile" 0 0
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	printf "# Swapfile\\n/swapfile none swap defaults 0 0\\n\\n" >> /etc/fstab
}

function networkd_config() {
	net_lot=$(networkctl --no-legend | grep -P "ether|wlan" | awk '{print $2}')
	for device in ${net_lot[*]}; do 
		((i++))
		cat > /etc/systemd/network/${device}.network <<-EOF
			[Match]
			Name=$device
			
			[Network]
			DHCP=ipv4
			
			[DHCP]
			RouteMetric=$(($i * 10))
		EOF
	done
}

function auto_log_in() {
	dialog --infobox "Configuring login." 3 23
	if [ $hostname = "gon" ]; then
		linsetting="--autologin $name"
	else
		linsetting="--skip-login --login-options $name"
	fi

	cat > /etc/systemd/system/getty@.service <<-EOF
		[Unit]
		Description=Getty on %I
		Documentation=man:agetty(8) man:systemd-getty-generator(8)
		Documentation=http://0pointer.de/blog/projects/serial-console.html
		After=systemd-user-sessions.service plymouth-quit-wait.service getty-pre.target

		# If additional gettys are spawned during boot then we should make
		# sure that this is synchronized before getty.target, even though
		# getty.target didn't actually pull it in.
		Before=getty.target
		IgnoreOnIsolate=yes

		# IgnoreOnIsolate causes issues with sulogin, if someone isolates
		# rescue.target or starts rescue.service from multi-user.target or
		# graphical.target.
		Conflicts=rescue.service
		Before=rescue.service

		# On systems without virtual consoles, don't start any getty. Note
		# that serial gettys are covered by serial-getty@.service, not this
		# unit.
		ConditionPathExists=/dev/tty0

		[Service]
		ExecStart=-/sbin/agetty $linsetting --noclear %I \$TERM

		Type=idle
		Restart=always
		RestartSec=0
		UtmpIdentifier=%I
		TTYPath=/dev/%I
		TTYReset=yes
		TTYVHangup=yes
		TTYVTDisallocate=yes
		KillMode=process
		IgnoreSIGPIPE=no
		SendSIGHUP=yes

		# Unset locale for the console getty since the console has problems
		# displaying some internationalized messages.
		UnsetEnvironment=LANG LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION

		[Install]
		WantedBy=getty.target
		DefaultInstance=tty1

	EOF

	systemctl daemon-reload &&
	systemctl reenable getty@tty1.service
}

function lock_sleep() {
	if [ -f /usr/bin/gdm ] && [ -f /usr/bin/i3lock ] && [ ! -f /usr/bin/sway ]; then
		cat > /etc/systemd/system/SleepLocki3@${name}.service <<-EOF
			#/etc/systemd/system/
			[Unit]
			Description=Turning i3lock on before sleep
			Before=sleep.target
			
			[Service]
			User=%I
			Type=forking
			Environment=DISPLAY=:0
			ExecStart=/usr/bin/i3lock -e -f -c 000000 -i /home/${name}/.config/wall.png -t
			ExecStartPost=/usr/bin/sleep 1
			
			[Install]
			WantedBy=sleep.target
		EOF
	fi
	systemctl enable SleepLocki3@${name}
}

function arduino_module() {
	if [ -f /usr/bin/arduino ]; then
		echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
		for group in {uucp,lock}; do
			sudo -u "$name" groups | grep $group >/dev/null 2>&1 || gpasswd -a $name $group
		done
	fi
}

function clone_dotfiles() {
	dialog --infobox "Downloading and installing config files..." 4 60
	cd /home/"$name"
	echo ".cfg" >> .gitignore
	rm .bash_profile .bashrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config --local status.showUntrackedFiles no
	rm .gitignore
}

dialog --infobox "Final configs." 3 18

echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

echo "vm.swappiness=10"         >> /etc/sysctl.d/99-sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf

grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc

sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh # Enable infinality fonts

[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

sudo -u "$name" groups | grep power >/dev/null 2>&1 || gpasswd -a $name power

[ ! -f /usr/bin/Xorg ] && rm /home/${name}/.xinitrc

if [ -f /usr/bin/gdm ]; then
	systemctl enable gdm
else
	auto_log_in
	lock_sleep
fi

if [ -f /usr/bin/NetworkManager ]; then
	systemctl enable NetworkManager
else
	networkd_config
	systemctl enable systemd-networkd
	systemctl enable systemd-resolved
fi

if [ $hostname = "killua" ]; then
	curl -sL "$repo/yarbs.d/killua.sh" > /tmp/killua.sh && source /tmp/killua.sh
	power_is_suspend
fi

create_swapfile
arduino_module
clone_dotfiles