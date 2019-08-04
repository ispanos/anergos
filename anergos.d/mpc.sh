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
		for tty in /dev/tty{1..6}; do /usr/bin/setleds -D +num < "$tty"; done
	EOF
	chmod +x /usr/bin/numlockOnTty
	systemctl enable numLockOnTty >/dev/null 2>&1
}

resolv_conf() {
	cat > /etc/resolv.conf <<-EOF
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
	for device in ${net_lot[*]}; do ((i++))
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
	log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \\\$TERM"
	[ "$1" = "auto" ] && 
	log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \\\$TERM"
	sed -i "s/ExecStart=.*/$log/" \
	/usr/lib/systemd/system/getty@.service > /etc/systemd/system/getty@.service
	systemctl daemon-reload 				>/dev/null 2>&1 
	systemctl reenable getty@tty1.service 	>/dev/null 2>&1
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
				--local status.showUntrackedFiles no > /dev/null 2>&1 && rm .gitignore; }

temps() {
	# https://aur.archlinux.org/packages/it87-dkms-git/ || https://github.com/bbqlinux/it87
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

dialog --infobox "Final configs." 3 18
[ -f /usr/bin/arduino ] && {
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep uucp >/dev/null 2>&1 || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep lock >/dev/null 2>&1 || gpasswd -a $name lock >/dev/null 2>&1 ; }
	sudo -u "$name" groups | grep power >/dev/null 2>&1 || gpasswd -a $name power >/dev/null 2>&1
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
echo "vm.swappiness=10"         >> /etc/sysctl.d/99-sysctl.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf
grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || 
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || 
	echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc
sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh
[ ! -f /usr/bin/Xorg ] && rm /home/${name}/.xinitrc
[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc
if [ -f /usr/bin/NetworkManager ]; then
	systemctl enable NetworkManager
else
	networkd_config >/dev/null 2>&1
	systemctl enable systemd-networkd >/dev/null 2>&1
	systemctl enable systemd-resolved >/dev/null 2>&1
fi
systemctl enable gdm 	>/dev/null 2>&1 || agetty_set && lock_sleep
create_swapfile 		>/dev/null 2>&1
clone_dotfiles
[ $hostname = "killua" ] && { power_is_suspend; temps; data; enable_numlk_tty; resolv_conf; }

cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel