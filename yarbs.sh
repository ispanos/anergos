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


function serviceinit() {
	for service in "$@"; do
		dialog --infobox "Enabling \"$service\"..." 4 40
		systemctl enable "$service"  > /dev/null 2>&1
	done
}

function newperms() {
	echo "$* " > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

function get_data(){
	[ -r autoconf.sh ] && source autoconf.sh
	curl -sL "$repo/yarbs.d/dialog_inputs.sh" > /tmp/dialog_inputs.sh
	source /tmp/dialog_inputs.sh
	get_inputs
	curl -sL "$repo/yarbs.d/arch_configuration.sh" > /tmp/arch_configuration.sh
	source /tmp/arch_configuration.sh
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
	serviceinit SleepLocki3@${name}
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

function set_root_pw() {
	printf "${rpwd1}\\n${rpwd1}" | passwd >/dev/null 2>&1
	unset rpwd1 rpwd2
}

function multi_plat_configs() {
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

	if [ $hostname = "killua" ]; then
		sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 
		curl -sL "$repo/yarbs.d/killua.sh" > /tmp/killua.sh 
		source /tmp/killua.sh
		enable_numlk_tty
		temps
		data
		resolv_conf
		rm killua.sh
	fi

	arduino_module
	clone_dotfiles
	set_root_pw
}

get_data
arch_config
create_swapfile
multi_plat_configs
newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: \
/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/pacman -Syu,/usr/bin/pacman -Syyuu,/usr/bin/pacman -Syyu,\
/usr/bin/systemctl restart NetworkManager,\
/usr/bin/systemctl restart systemd-networkd,\
/usr/bin/systemctl restart systemd-resolved"