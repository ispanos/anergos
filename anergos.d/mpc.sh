#!/usr/bin/env bash

function nobeep() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function all_core_make() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 && return
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function nano_configs() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || 
	echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function infinality(){
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function office_logo() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function create_swapfile() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	fallocate -l 2G /swapfile 	>/dev/null 2>&1
	chmod 600 /swapfile
	mkswap /swapfile 			>/dev/null 2>&1
	swapon /swapfile 			>/dev/null 2>&1
	printf "# Swapfile\\n/swapfile none swap defaults 0 0\\n\\n" >> /etc/fstab
	printf "vm.swappiness=10\nvm.vfs_cache_pressure=50\n" > /etc/sysctl.d/99-sysctl.conf
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function clone_dotfiles() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	cd /home/"$name" && echo ".cfg" >> .gitignore && rm .bash_profile .bashrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config \
				--local status.showUntrackedFiles no > /dev/null 2>&1 && rm .gitignore
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function arduino_groups() {
	if [ ! -f /usr/bin/arduino ] && [ $1 ] && [ $1 -eq 0 ]; then
		echo $(tput setaf 1)"${FUNCNAME[0]} skipped (value $1)"$(tput sgr0) && return
	fi

	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep uucp >/dev/null 2>&1 || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep lock >/dev/null 2>&1 || gpasswd -a $name lock >/dev/null 2>&1
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function networkd_config() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return

	if [ -f  /usr/bin/NetworkManager ]; then
		systemctl enable NetworkManager >/dev/null 2>&1
		echo $(tput setaf 2)"NetworkManager done (value $1)"$(tput sgr0)

	else
		net_lot=$(networkctl --no-legend 2>/dev/null | grep -P "ether|wlan" | awk '{print $2}')
		for device in ${net_lot[*]}; do ((i++))
			cat > /etc/systemd/network/${device}.network <<-EOF
				[Match]
				Name=${device}
				[Network]
				DHCP=ipv4
				[DHCP]
				RouteMetric=$(($i * 10))
			EOF
		done
		systemctl enable systemd-networkd >/dev/null 2>&1
		systemctl enable systemd-resolved >/dev/null 2>&1
		echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
	fi 
	
}

function power_group() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	gpasswd -a $name power >/dev/null 2>&1
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function agetty_set() {
	systemctl enable gdm >/dev/null 2>&1 && 
		echo $(tput setaf 2)"GDM done (value $1)"$(tput sgr0) && return
	
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	if [ "$1" = "auto" ]; then
		local log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \$TERM"
	else
		local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	fi
	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > /etc/systemd/system/getty@.service
	systemctl daemon-reload 				>/dev/null 2>&1
	systemctl reenable getty@tty1.service 	>/dev/null 2>&1
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function virtualbox() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return

	if [[ $(lspci | grep VirtualBox) ]]; then
		if [ -f /usr/bin/pacman ]; then
			pacman -S --noconfirm virtualbox-guest-modules-arch virtualbox-guest-utils >/dev/null 2>&1

			if [ -f /usr/bin/virtualbox ]; then
				pacman -Rns --noconfirm virtualbox >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-host-modules-arch >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-guest-iso >/dev/null 2>&1 
				echo "Removed VirtualBox. This is a virtualbox guest"
			fi
			echo $(tput setaf 2)"${FUNCNAME[0]}-guest done (value $1)"$(tput sgr0)
		else
			echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0)
		fi


	elif [ -f /usr/bin/virtualbox ]; then
		sudo -u "$name" groups | grep vboxusers >/dev/null 2>&1 || 
			gpasswd -a $name vboxusers >/dev/null 2>&1
		echo $(tput setaf 2)"${FUNCNAME[0]}-host done (value $1)"$(tput sgr0)
	fi
}

function lock_sleep() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	if [ -f /usr/bin/i3lock ] && [ ! -f /usr/bin/sway ]; then
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
	systemctl enable SleepLocki3@${name} >/dev/null 2>&1
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function resolv_conf() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	printf "search home\\nnameserver 192.168.1.1\\n" > /etc/resolv.conf
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function enable_numlk_tty() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	cat > /etc/systemd/system/numLockOnTty.service <<-EOF
		[Unit]
		Description=numlockOnTty
		[Service]
		ExecStart=/usr/bin/numlockOnTty
		[Install]
		WantedBy=multi-user.target
	EOF
	cat > /usr/bin/numlockOnTty <<-EOF
		#!/usr/bin/env bash

		for tty in /dev/tty{1..6}
		do
		    /usr/bin/setleds -D +num < "$tty";
		done

	EOF
	chmod +x /usr/bin/numlockOnTty
	systemctl enable numLockOnTty >/dev/null 2>&1
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function temps() { # https://aur.archlinux.org/packages/it87-dkms-git/ || https://github.com/bbqlinux/it87
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	[ ! -f /usr/bin/yay ] && return
	sudo -u "$name" yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
	echo "it87" > /etc/modules-load.d/it87.conf
	echo "it87-dkms-git" >> /home/"$name"/.local/Fresh_pack_list
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function data() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	mkdir -p /media/Data
	cat >> /etc/fstab <<-EOF
		# /dev/sda1 LABEL=data
		UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4  /media/Data    ext4 rw,noatime,nofail,user,auto    0  2
	
	EOF
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

function powerb_is_suspend() {
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"${FUNCNAME[0]} skipped"$(tput sgr0) && return
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
	echo $(tput setaf 2)"${FUNCNAME[0]} done (value $1)"$(tput sgr0)
}

# Needed Permissions
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel

nobeep 				1
all_core_make 		1
nano_configs 		1
infinality 			1
office_logo 		1
create_swapfile 	1
clone_dotfiles 		1
arduino_groups 		1
networkd_config 	1
power_group 		1
agetty_set			1
lock_sleep			1

[ $hostname = "killua" ] && { echo "killua:"
	virtualbox 1
	resolv_conf 1
	enable_numlk_tty 1
	temps 1
	data 1
}

# Sane Permissions
cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel

sleep 15
