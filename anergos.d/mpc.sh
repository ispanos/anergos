#!/usr/bin/env bash

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/ispanos/dotfiles.git"

function chech_val() {
	printf $(tput setaf 3)"${FUNCNAME[1]}....\t\t - "$(tput sgr0)
	[ $1 ] && [ $1 -eq 0 ] && echo $(tput setaf 1)"skipped"$(tput sgr0)
}

function ready() {
 echo $(tput setaf 2)"done"$@$(tput sgr0)
}

function nobeep() {
	chech_val $1 && return
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
	ready
}

function power_group() {
	chech_val $1 && return
	gpasswd -a $name power >/dev/null 2>&1
	ready
}

function all_core_make() {
	chech_val $1 && return
	grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 &&
	ready "- '^MAKEFLAGS' exists" && return
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	ready
}

function networkd_config() {
	chech_val $1 && return
	if [ -f  /usr/bin/NetworkManager ]; then
		systemctl enable NetworkManager >/dev/null 2>&1
		ready " (NetworkManager)"

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
		ready
	fi 
	
}

function nano_configs() {
	chech_val $1 && return
	grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || 
	echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc
	ready
}

function infinality(){
	chech_val $1 && return
	sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh
	ready
}

function office_logo() {
	chech_val $1 && return
	[ -f /etc/libreoffice/sofficerc ] || 
	chech_val 0 && return
	sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc	
	ready
}

function create_swapfile() {
	chech_val $1 && return
	fallocate -l 2G /swapfile 	>/dev/null 2>&1
	chmod 600 /swapfile
	mkswap /swapfile 			>/dev/null 2>&1
	swapon /swapfile 			>/dev/null 2>&1
	printf "# Swapfile\\n/swapfile none swap defaults 0 0\\n\\n" >> /etc/fstab
	printf "vm.swappiness=10\nvm.vfs_cache_pressure=50\n" > /etc/sysctl.d/99-sysctl.conf
	ready
}

function clone_dotfiles() {
	chech_val $1 && return
	cd /home/"$name" && echo ".cfg" >> .gitignore && rm .bash_profile .bashrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config \
				--local status.showUntrackedFiles no > /dev/null 2>&1 && rm .gitignore
	ready
}

function arduino_groups() {
	chech_val && return
	[ ! -f /usr/bin/arduino ] && chech_val 0 && return
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep uucp >/dev/null 2>&1 || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep lock >/dev/null 2>&1 || gpasswd -a $name lock >/dev/null 2>&1
	ready
}

function agetty_set() {
	systemctl enable gdm >/dev/null 2>&1 && ready " GDM (value $1)" && return
	chech_val $1 && return
	if [ "$1" = "auto" ]; then
		local log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \$TERM"
	else
		local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	fi
	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service
	systemctl daemon-reload >/dev/null 2>&1; systemctl reenable getty@tty1.service >/dev/null 2>&1
	ready " (value $1)"
}

function lock_sleep() {
	chech_val $1 && return
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
	ready
}

function virtualbox() {
	chech_val $1 && return

	if [[ $(lspci | grep VirtualBox) ]]; then
		
		if hostnamectl | grep -q "Arch Linux"; then
			local g_utils="virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware"
			pacman -S --noconfirm $g_utils >/dev/null 2>&1

			if [ -f /usr/bin/virtualbox ]; then
				printf "Removing VirtualBox... "
				pacman -Rns --noconfirm virtualbox >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-host-modules-arch >/dev/null 2>&1
				pacman -Rns --noconfirm virtualbox-guest-iso >/dev/null 2>&1 
			fi
			ready " - guest"
		else
			echo $(tput setaf 1)"- Guest is not ArchLinux"$(tput sgr0)
		fi


	elif [ -f /usr/bin/virtualbox ]; then
		sudo -u "$name" groups | grep vboxusers >/dev/null 2>&1 || 
			gpasswd -a $name vboxusers >/dev/null 2>&1
		ready " - host"
	fi
}

function resolv_conf() {
	chech_val $1 && return
	printf "search home\\nnameserver 192.168.1.1\\n" > /etc/resolv.conf && ready
}

function enable_numlk_tty() {
	chech_val $1 && return
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
	chmod +x /usr/bin/numlockOnTty; systemctl enable numLockOnTty >/dev/null 2>&1
	ready
}

function temps() { # https://aur.archlinux.org/packages/it87-dkms-git || github.com/bbqlinux/it87
	chech_val $1 && return
	[ ! -f /usr/bin/yay ] && chech_val 0 && return
	sudo -u "$name" yay -S --noconfirm it87-dkms-git >/dev/null 2>&1
	echo "it87" > /etc/modules-load.d/it87.conf
	printf "\nit87-dkms-git\n" >> /home/"$name"/.local/Fresh_pack_list
	ready
}

function data() {
	chech_val $1 && return
	mkdir -p /media/Data
	cat >> /etc/fstab <<-EOF
		# /dev/sda1 LABEL=data
		UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4 /media/Data ext4 rw,noatime,nofail,user,auto 0 2
	
	EOF
	ready
}

function powerb_is_suspend() {
	chech_val $1 && return
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
	ready
}

function set_sane_permitions() {
cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel
echo $(tput setaf 2)"${FUNCNAME[0]}- in $0 Done!"$(tput sgr0)
sleep 15
}

trap set_sane_permitions EXIT

# Needed Permissions
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel

nobeep; power_group; all_core_make; networkd_config; nano_configs; infinality; office_logo
create_swapfile
clone_dotfiles
arduino_groups
agetty_set
lock_sleep
powerb_is_suspend 0
[ $hostname = "killua" ] && { 
					echo "killua:"; virtualbox; resolv_conf; enable_numlk_tty; temps; data; }
