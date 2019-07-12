#!/bin/bash

# Arch Bootstraping script
# License: GNU GPLv3
error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}
[ ! -d "/sys/firmware/efi" ] && error "Please reboot to UEFI mode."

timezone="Europe/Athens"
aurhelper="yay"

i3="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/i3.csv"
coreprogs="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/progs.csv"
common="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/common.csv"
sway="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/sway.csv"
gnome="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/gnome.csv"

help() {
	echo  "# -p 			Sets \$prog_files. Add your own link(s) with the list(s) of packages you want to install. -- Overides defaults."
	echo  "# -m 			Enable multilib."
	echo  "# -d <link> ' 	to set your own dotfiles's repo."
}
while getopts "mhd:p:" option; do 
	case "${option}" in
		m) multi_lib_bool="true" ;;
		d) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
		p) prog_files=${OPTARG} ;;
		h) help && exit ;;
		*) printf "Invalid option: -%s\\n" "$OPTARG" ;;
	esac 
done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/ispanos/dotfiles.git"
[ -z "$prog_files" ] && prog_files="$i3 $coreprogs $common"



get_dialog() {
	echo "Installing dialog, to make things look better..."
	pacman --noconfirm -Syyu dialog >/dev/null 2>&1
}

get_deps() {
	dialog --title "First things first." --infobox "Installing 'base-devel', 'git', and 'linux-headers'." 3 60
	pacman --noconfirm --needed linux-headers git base-devel >/dev/null 2>&1
}

get_hostname() { hostname=$(dialog --inputbox "Please enter the hostname." 10 60 3>&1 1>&2 2>&3 3>&1) || exit; }
confirm_n_go() { dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35 ; }

get_userandpass() {
	# Prompts user for new username an password.
	name=$(dialog --inputbox "Please enter a name for a user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit

	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do	
		name=$(dialog --no-cancel --inputbox "Name not valid. Start with a letter, use lowercase letters, - or _" 10 60 3>&1 1>&2 2>&3 3>&1)
	done

	upwd1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	upwd2=$(dialog --no-cancel --passwordbox "Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)
	
	while ! [ "$upwd1" = "$upwd2" ]; do
		unset upwd2
		upwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		upwd2=$(dialog --no-cancel --passwordbox "Retype user password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

get_root_pass() {
	# Prompts user for new username an password.
	rpwd1=$(dialog --no-cancel --passwordbox "Enter root user's password." 10 60 3>&1 1>&2 2>&3 3>&1)
	rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
	
	while ! [ "$rpwd1" = "$rpwd2" ]; do
		unset rpwd2
		rpwd1=$(dialog --no-cancel --passwordbox "Passwords didn't match. Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
		rpwd2=$(dialog --no-cancel --passwordbox "Retype root user password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

set_locale_time() {
	dialog --infobox "Locale and time-sync..." 0 0
	serviceinit systemd-timesyncd.service
	ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
	hwclock --systohc
	sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
	locale-gen > /dev/null 2>&1
	echo 'LANG="en_US.UTF-8"' > /etc/locale.conf
}

######   For LVM/LUKS modify /etc/mkinitcpio.conf   ######
######   sed for HOOKS="...keyboard encrypt lvm2"   ######
######   umkinitcpio -p linux && linux-lts entry?   ######

systemd_boot() {

	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
		*)				cpu="no" 	;;
	esac

	if [ $cpu != "no" ]; then
		dialog --infobox "Installing ${cpu} microcode." 3 31
		pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
	fi
	
	# Installs systemd-boot to the eps partition
	dialog --infobox "Setting-up systemd-boot" 0 0
	bootctl --path=/boot install
	 
	# Creates pacman hook to update systemd-boot after package upgrade.
	mkdir -p /etc/pacman.d/hooks
	cat > /etc/pacman.d/hooks/bootctl-update.hook <<-EOF
		[Trigger]
		Type = Package
		Operation = Upgrade
		Target = systemd
		
		[Action]
		Description = Updating systemd-boot
		When = PostTransaction
		Exec = /usr/bin/bootctl update
	EOF
	 
	# Creates loader.conf. Stored in files/ folder on repo.
	cat > /boot/loader/loader.conf <<-EOF
		default  arch
		console-mode max
		editor   no
	EOF
	
	# sets uuidroot as the UUID of the partition mounted at "/".
	uuidroot="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"
	
	# Creates loader entry for root partition, using the "linux" kernel
						echo "title   Arch Linux"           >  /boot/loader/entries/arch.conf
						echo "linux   /vmlinuz-linux"       >> /boot/loader/entries/arch.conf
	[ $cpu = "no" ] || 	echo "initrd  /${cpu}-ucode.img"    >> /boot/loader/entries/arch.conf
						echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf
						echo "options root=${uuidroot} rw"  >> /boot/loader/entries/arch.conf
}

serviceinit() { 
	for service in "$@"; do
		dialog --infobox "Enabling \"$service\"..." 4 40
		systemctl enable "$service"
	done
}

pacman_stuff() {
	dialog --infobox "Performance tweaks. (pacman/yay)" 0 0
	
	# Creates pacman hook to keep only the 3 latest versions of packages.
	cat > /etc/pacman.d/hooks/cleanup.hook <<-EOF
		[Trigger]
		Type = Package
		Operation = Remove
		Operation = Install
		Operation = Upgrade
		Target = *
		
		[Action]
		Description = Keeps only the latest 3 versions of packages
		When = PostTransaction
		Exec = /usr/bin/paccache -rk3
	EOF

	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
	grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
}

swap_stuff() {
	dialog --infobox "Creating swapfile" 0 0
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	printf "\\n#Swapfile\\n/swapfile none swap defaults 0 0\\n" >> /etc/fstab
	
	# Sets swappiness and cache pressure for better performance.
	echo "vm.swappiness=10"         >> /etc/sysctl.d/99-sysctl.conf
	echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf
}

disable_beep() { 
	dialog --infobox "Disabling 'beep error' sound." 10 50
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

multilib() { 
	# Enables multilib unless argument "-m false" was set when running yarbs.
	if [ "$multi_lib_bool" ]; then
		dialog --infobox "Enabling multilib..." 0 0
		sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
		pacman --noconfirm --needed -Sy >/dev/null 2>&1
		pacman -Fy >/dev/null 2>&1
	fi
}

create_user() {
	# Adds user `$name` with password $upwd1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -g wheel -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$upwd1" | chpasswd
	unset upwd1 upwd2
}

newperms() {
	# Set special sudoers settings for install (or after).
	echo "$* " > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel
}

clone_dotfiles() {
	dialog --infobox "Downloading and installing config files..." 4 60
	cd /home/"$name"
	echo ".cfg" >> .gitignore
	rm .bash_profile .bashrc .xinitrc
	sudo -u "$name" git clone --bare "$dotfilesrepo" /home/${name}/.cfg > /dev/null 2>&1 
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} checkout
	sudo -u "$name" git --git-dir=/home/${name}/.cfg/ --work-tree=/home/${name} config --local status.showUntrackedFiles no
	rm .gitignore
}

maininstall() { # Installs all needed programs from main repo.
	dialog --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	pacman --noconfirm --needed -S "$1" > /dev/null 2>&1
}

gitmakeinstall() {
	dir=$(mktemp -d)
	dialog  --infobox "Installing \`$(basename "$1")\` ($n of $total). $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" > /dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return
}

aurinstall() {
	dialog  --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep "^$1$" > /dev/null 2>&1 && return
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	dialog --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

mergeprogsfiles() {
	for list in ${prog_files}; do
		if [ -f "$list" ]; then
			cat "$list" >> /tmp/progs.csv
		else
			curl -Ls "$list" | sed '/^#/d' >> /tmp/progs.csv
		fi
	done
}

installationloop() {
	mergeprogsfiles 
	pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1
	
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qm | awk '{print $1}')
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"")  maininstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"A") aurinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"G") gitmakeinstall "$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
			"P") pipinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		esac
	done < /tmp/progs.csv
}

aur_helper_inst() { 
	dialog --infobox "Installing \"${aurhelper}\"..." 4 50
	cd /tmp || exit
	curl -sO "https://aur.archlinux.org/cgit/aur.git/snapshot/${aurhelper}.tar.gz" &&
	sudo -u "$name" tar -xvf ${aurhelper}.tar.gz >/dev/null 2>&1 &&
	cd ${aurhelper} && sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return
}

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

	serviceinit numlock
}

i3_lock_sleep() {
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

	serviceinit SleepLocki3@yiannis
}

config_killua() {
	[ $hostname = "killua" ] && (
	enable_numlk_tty
	i3_lock_sleep
	dialog --infobox "Killua..." 0 0
	# Temp_Asus_X370_Prime_pro
	sudo -u "$name" $aurhelper -S --noconfirm it87-dkms-git >/dev/null 2>&1
	echo "it87" > /etc/modules-load.d/it87.conf
	sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf 
	
	cat > /etc/resolv.conf <<-EOF
		# Resolver configuration file.
		# See resolv.conf(5) for details.
		search home
		nameserver 192.168.1.1
	EOF
	)
}

networkd_init() {
	# Starts networkd as a network manager and configures ethernet.
	cat > /etc/systemd/network/en.network <<-EOF
		[Match]
		Name=en*
		
		[Network]
		DHCP=ipv4
		
		[DHCP]
		RouteMetric=10
	EOF

	cat > /etc/systemd/network/wl.network <<-EOF
		[Match]
		Name=wl*
		
		[Network]
		DHCP=ipv4
		
		[DHCP]
		RouteMetric=20
	EOF

	serviceinit systemd-networkd systemd-resolved
}

init_net_manage() {
	if [ -f /usr/bin/NetworkManager ]; then
		serviceinit NetworkManager
	else
		networkd_init
	fi
}

config_network() {
	dialog --infobox "Configuring network.." 0 0
	echo $hostname > /etc/hostname
	cat > /etc/hosts <<-EOF
		#<ip-address>   <hostname.domain.org>    <hostname>
		127.0.0.1       localhost.localdomain    localhost
		::1             localhost.localdomain    localhost
		127.0.1.1       ${hostname}.localdomain  $hostname
	EOF

	init_net_manage
}

set_root_pw() {
	printf "${rpwd1}\\n${rpwd1}" | passwd
	unset rpwd1 rpwd2
}

create_pack_ref() {
	dialog --infobox "Removing orphans..." 0 0
	pacman --noconfirm -Rns $(pacman -Qtdq)
	sudo -u "$name" mkdir -p /home/"$name"/.local/
	# creates a list of all installed packages for future reference
	pacman -Qq > /home/"$name"/.local/Fresh_pack_list
}

final_sys_settigs() {
	sed -i 's/^#exp/exp/;s/version=40"$/version=38"$/' /etc/profile.d/freetype2.sh # Enable infinality fonts
	[ -f /usr/bin/gdm ] && serviceinit gdm
	[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc
}

##|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
##                 Start                    |||||||||||||||||||||
##|||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
get_dialog		|| error "Check your internet connection?"
get_hostname    || error "User exited"
get_userandpass || error "User exited."
get_root_pass   || error "User exited."
confirm_n_go 	|| { clear; exit; }
get_deps
set_locale_time
systemd_boot
pacman_stuff
swap_stuff
disable_beep
multilib
create_user 	|| error "Error adding user."
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"
aur_helper_inst || error "Failed to install AUR helper." # Requires user.
installationloop
clone_dotfiles
config_killua
config_network
create_pack_ref
final_sys_settigs
set_root_pw

newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: \
/usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,\
/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/pacman -Syu,/usr/bin/pacman -Syyuu,/usr/bin/pacman -Syyu,\
/usr/bin/systemctl restart NetworkManager,\
/usr/bin/systemctl restart systemd-networkd,\
/usr/bin/systemctl restart systemd-resolved"
