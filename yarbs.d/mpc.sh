#!/bin/bash

function power_is_suspend() {
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf;}

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

function agetty_set() {
	cp /usr/lib/systemd/system/getty@.service /etc/systemd/system/getty@.service
	log="ExecStart=-/sbin/agetty --skip-login --login-options $name --noclear %I \\\$TERM"
	[ "$1" = "auto" ] && 
	log="ExecStart=-/sbin/agetty --autologin $name --noclear %I \\\$TERM"
	sed -i "s/ExecStart=.*/$log/" /etc/systemd/system/getty@.service
	systemctl daemon-reload && systemctl reenable getty@tty1.service >/dev/null 2>&1
}

function lock_sleep() {
	if [ -f /usr/bin/i3lock ] && [ ! -f /usr/bin/gdm ] && [ ! -f /usr/bin/sway ]; then
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

function clone_dotfiles() {
	dialog --infobox "Downloading and installing config files..." 4 60
	cd /home/"$name" && echo ".cfg" >> .gitignore && rm .bash_profile .bashrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config \
					--local status.showUntrackedFiles no > /dev/null 2>&1 && rm .gitignore
}

dialog --infobox "Final configs." 3 18

echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

echo "vm.swappiness=10"         >> /etc/sysctl.d/99-sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf

grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || 
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || 
	echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc

sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh

[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

sudo -u "$name" groups | grep power >/dev/null 2>&1 || gpasswd -a $name power

[ ! -f /usr/bin/Xorg ] && rm /home/${name}/.xinitrc

if [ -f /usr/bin/NetworkManager ]; then
	systemctl enable NetworkManager
else
	networkd_config
	systemctl enable systemd-networkd >/dev/null 2>&1
	systemctl enable systemd-resolved >/dev/null 2>&1
fi

if [ -f /usr/bin/arduino ]; then
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep uucp >/dev/null 2>&1 || gpasswd -a $name uucp
	sudo -u "$name" groups | grep lock >/dev/null 2>&1 || gpasswd -a $name lock
fi

[ $hostname = "killua" ] && {
curl -sL "$repo/yarbs.d/killua.sh" > /tmp/kil.sh; source /tmp/kil.sh; power_is_suspend; }

systemctl enable gdm || agetty_set && lock_sleep
create_swapfile
clone_dotfiles