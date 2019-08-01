#!/bin/bash

# Arch Bootstraping script
# License: GNU GPLv3
function error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

timezone="Europe/Athens"
lang="en_US.UTF-8"

repo=https://raw.githubusercontent.com/ispanos/YARBS/master

i3="$repo/programs/i3.csv"
coreprogs="$repo/programs/progs.csv"
common="$repo/programs/common.csv"
sway="$repo/programs/sway.csv"
gnome="$repo/programs/gnome.csv"

function help() {
	cat <<-EOF
		Multilib:
		  -m             Enable multilib.

		Dotfiles:
		  -d <link>      to set your own dotfiles's repo. By default it uses my own dotfiles repository.

		Packages:
		  -p             Add your own link(s) with the list(s) of packages you want to install. -- Overides defaults.

		Example: yarbs -p link1 link2 file1 -m -d https://yourgitrepo123.xyz/dotfiles
		Visit the original repo https://github.com/ispanos/yarbs.git for more info.
	EOF
}

while getopts "mhd:p:" option; do
	case "${option}" in
		m) multi_lib_bool="true" ;;
		d) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
		p) prog_files=${OPTARG} ;;
		h) help && exit ;;
		*) help && exit  ;;
	esac
done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/ispanos/dotfiles.git"
[ -z "$prog_files" ] && prog_files="$i3 $coreprogs $common"
#[ -z "$prog_files" ] && prog_files="$sway $coreprogs $common"


# Used in more that one place.
function serviceinit() {
	for service in "$@"; do
		dialog --infobox "Enabling \"$service\"..." 4 40
		systemctl enable "$service"
	done
}

function get_dialog() {
	echo "Installing dialog, to make things look better..."
	pacman --noconfirm -Syyu dialog >/dev/null 2>&1
}

function get_hostname() { 
	if [ -z "$hostname" ]; then
		hostname=$(dialog --inputbox "Please enter the hostname." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
		automated=false
	fi
}

function get_userandpass() {
	if [ -z "$name" ]; then 
		# Prompts user for new username an password.
		name=$(dialog --inputbox "Please enter a name for a user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
	fi

	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Name not valid. Start with a letter, use lowercase letters, - or _" 10 60 3>&1 1>&2 2>&3 3>&1)
	done

	if [ -z "$user_password" ]; then
		upwd1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
		upwd2=$(dialog --no-cancel --passwordbox "Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)

		while ! [ "$upwd1" = "$upwd2" ]; do
			unset upwd2
			upwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)
			upwd2=$(dialog --no-cancel --passwordbox "Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done

		automated=false

	else
		upwd1=$user_password
		upwd2=$user_password
	fi
}

function get_root_pass() {
	if [ -z "$root_password" ]; then 
		# Prompts user for new username an password.
		rpwd1=$(dialog --no-cancel --passwordbox "Enter root user's password." 10 60 3>&1 1>&2 2>&3 3>&1)
		rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)

		while ! [ "$rpwd1" = "$rpwd2" ]; do
			unset rpwd2
			rpwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
			rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done
	
		automated=false
	else
		rpwd1=$root_password
		rpwd2=$root_password
	fi
}

function confirm_n_go() {
	if [ "$automated" = "false" ]; then
		dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35
	fi
}

function pre_start(){
	get_dialog
	source autoconf.sh
	get_hostname
	get_userandpass
	get_root_pass
	confirm_n_go
}

function arch_config() {
	curl -sL "$repo/yarbs.d/arch_configuration.sh" > autoconf.sh
	source autoconf.sh
	set_locale_time
	config_network
	inst_bootloader
	pacman_stuff
	rm autoconf.sh
}

function create_swapfile() {
	dialog --infobox "Creating swapfile" 0 0
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	printf "# Swapfile\\n/swapfile none swap defaults 0 0\\n\\n" >> /etc/fstab
}

function newperms() {
	# Set special sudoers settings for install (or after).
	echo "$* " > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

function create_user() {
	# Adds user `$name` with password $upwd1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$upwd1" | chpasswd
	unset upwd1 upwd2
	# Temporarily give wheel that privilages.
	newperms "%wheel ALL=(ALL) NOPASSWD: ALL"
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

function disable_beep() {
	dialog --infobox "Disabling 'beep error' sound." 10 50
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

function create_pack_ref() {
	dialog --infobox "Removing orphans..." 0 0
	pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
	sudo -u "$name" mkdir -p /home/"$name"/.local/
	# creates a list of all installed packages for future reference
	pacman -Qq > /home/"$name"/.local/Fresh_pack_list
}

function auto_log_in() {
	dialog --infobox "Configuring login." 3 23
	if [ $hostname = "gon" ]; then
		#  Actual auto-login.
		linsetting="--autologin $name"
	else
		#  Username auto-type.
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
	serviceinit SleepLocki3@${name}
}

function arduino_module() {
	#https://wiki.archlinux.org/index.php/Arduino
	if [ -f /usr/bin/arduino ]; then
		for group in {uucp,lock}; do
			sudo -u "$name" gropus >/dev/null 2>&1 || gpasswd -a $name $group
		done

		cat > /etc/modules-load.d/cdc_acm.conf <<-EOF
			# https://wiki.archlinux.org/index.php/Arduino
			# Load cdc_acm module for arduino
			cdc_acm
		EOF
	fi
}

function set_root_pw() {
	printf "${rpwd1}\\n${rpwd1}" | passwd >/dev/null 2>&1
	unset rpwd1 rpwd2
}

function final_sys_settigs() {
	dialog --infobox "Final configs." 3 18
	
	disable_beep
	
	arduino_module

	# Sets swappiness and cache pressure for better performance.
	echo "vm.swappiness=10"         >> /etc/sysctl.d/99-sysctl.conf
	echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf

	grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

	grep '^include "/usr/share/nano/*.nanorc"' /etc/nanorc >/dev/null 2>&1 || echo 'include "/usr/share/nano/*.nanorc"' >> /etc/nanorc

	sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh # Enable infinality fonts

	[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

	[ ! -f /usr/bin/Xorg ] && rm /home/${name}/.xinitrc

	if [ -f /usr/bin/gdm ]; then
		serviceinit gdm
	else
		auto_log_in
		lock_sleep
	fi


	if [ -f /usr/bin/NetworkManager ]; then
		serviceinit NetworkManager
	else
		networkd_config && serviceinit systemd-networkd systemd-resolved
	fi

	set_root_pw
}

function config_killua() {
	if [ $hostname = "killua" ]; then
		sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 

		curl -sL "$repo/yarbs.d/killua.sh" > killua.sh 
		source killua.sh
		enable_numlk_tty
		temps
		data
		resolv_conf
		rm killua.sh
	fi
}

pre_start
arch_config
create_user
installationloop
clone_dotfiles
config_killua
create_pack_ref
create_swapfile
final_sys_settigs
newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: \
/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/pacman -Syu,/usr/bin/pacman -Syyuu,/usr/bin/pacman -Syyu,\
/usr/bin/systemctl restart NetworkManager,\
/usr/bin/systemctl restart systemd-networkd,\
/usr/bin/systemctl restart systemd-resolved"
