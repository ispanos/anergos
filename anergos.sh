#!/usr/bin/env bash
# License: GNU GPLv3

## Archlinux installation ##
get_username() {
# Ask for the name of the main user.
	read -rep $'Please enter a name for a user account: \n' get_name

	while ! echo "$get_name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		read -rep $'Invalid name. Start with a letter, use lowercase letters, - or _ : \n' get_name
	done
    echo $get_name
	unset get_name
}


get_pass() {
	# Pass the name of the user as an argument.
    cr=`echo $'\n.'`; cr=${cr%.}
    get_pwd_name="$1"
    read -rsep $"Enter a password for $get_pwd_name: $cr" get_pwd_pass
    read -rsep $"Retype ${get_pwd_name}'s password: $cr" check_4_pass

    while ! [ "$get_pwd_pass" = "$check_4_pass" ]; do unset check_4_pass
        read -rsep $"Passwords didn't match. Retype ${get_pwd_name}'s password: " get_pwd_pass
        read -rsep $"Retype ${get_pwd_name}'s password: " check_4_pass
    done

    echo "$get_pwd_pass"
    unset get_pwd_pass check_4_pass
}


systemd_boot() {
	# Installs and configures systemd-boot. (only for archlinux atm.)
	bootctl --path=/boot install >/dev/null 2>&1

	cat > /boot/loader/loader.conf <<-EOF
		default  ArchLinux
		console-mode max
		editor   no
	EOF

	local root_id="$(lsblk --list -fs -o MOUNTPOINT,UUID | \
					grep "^/ " | awk '{print $2}')"

	kernel_parms="rw quiet" # Default kernel parameters.

	# I need this to avoid random crashes on my main pc (AMD ryzen R5 1600)
	# https://forum.manjaro.org/t/amd-ryzen-problems-and-fixes/55533
	lscpu | grep -q "AMD Ryzen" && kernel_parms="$kernel_parms idle=nowait"

	# Bootloader entry using `linux` kernel:
	cat > /boot/loader/entries/ArchLinux.conf <<-EOF
		title   Arch Linux
		linux   /vmlinuz-linux
		initrd  /${cpu}-ucode.img
		initrd  /initramfs-linux.img
		options root=UUID=${root_id} $kernel_parms
	EOF

	# A pacman hook to update systemd-boot after systemd packages is updated.
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
}


grub_mbr() {
	# grub option is not tested much and only works on MBR partition tables
	# Avoid using it as is.
	pacman --noconfirm --needed -S grub
	grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | \
				grep "^/ " | awk '{print $2}')
	grub-install --target=i386-pc $grub_path >/dev/null 2>&1
	grub-mkconfig -o /boot/grub/grub.cfg
}


core_arch_install() {
	echo ":: Setting up Arch"
	
	systemctl enable --now systemd-timesyncd.service >/dev/null 2>&1
	ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
	
	hwclock --systohc
	
	sed -i "s/#${lang} UTF-8/${lang} UTF-8/g" /etc/locale.gen
	locale-gen > /dev/null 2>&1
	
	echo 'LANG="'$lang'"' > /etc/locale.conf
	
	echo $hostname > /etc/hostname
	
	cat > /etc/hosts <<-EOF
		#<ip-address>   <hostname.domain.org>    <hostname>
		127.0.0.1       localhost.localdomain    localhost
		::1             localhost.localdomain    localhost
		127.0.1.1       ${hostname}.localdomain  $hostname
	EOF
	
	# Enable [multilib] repo, if multi_lib_bool == true and sync database. -Sy
	if [ "$multi_lib_bool" = true  ]; then
		sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
		echo ":: Synchronizing package databases - [multilib]"
		pacman -Sy >/dev/null 2>&1
		pacman -Fy >/dev/null 2>&1
	fi

	# Install cpu microcode.
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
	esac

	pacman --noconfirm --needed -S "${cpu}-ucode"
	
	# This folder is needed for pacman hooks. (needed for systemd-boot)
	mkdir -p /etc/pacman.d/hooks

	# Install bootloader
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot
		pacman --noconfirm --needed -S efibootmgr
	else
		grub_mbr
	fi

	# Set root password
	if [ -z "$root_password" ]; then
		printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1
	fi

	echo "blacklist pcspkr" >> /etc/modprobe.d/beep.conf

	# Create user
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	# Set user password.
	echo "$name:$user_password" | chpasswd

	pacman --noconfirm --needed -S \
		base-devel git linux linux-headers linux-firmware \
		man-db man-pages usbutils pacman-contrib expac arch-audit

	echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
	chmod 440 /etc/sudoers.d/wheel

	# Use all cpu cores to compile packages
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf

	echo ":: Installing - yay-bin"
	sudo -u "$name" git clone -q https://aur.archlinux.org/yay-bin.git /tmp/yay
	cd /tmp/yay && sudo -u "$name" makepkg -si --noconfirm >/dev/null 2>&1
}


install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi

	# Merges all csv files in one file. Checks for local files first.
	for file in $@; do
		if [ -r programs/${file}.csv ]; then
			cat programs/${lsb_dist}.${file}.csv >> /tmp/progs.csv
		else
			curl -Ls "${progs_repo}${lsb_dist}.${file}.csv" >> /tmp/progs.csv
		fi
	done

    sudo -u "$name" yay -S --noconfirm --needed \
	$(cat /tmp/progs.csv | sed '/^#/d;/^,/d;s/,.*$//' | tr "\n" " ")
}





# Prints the name of the parent function or a prettified output.
status_msg() { printf "%-25s %2s" $(tput setaf 4)"${FUNCNAME[1]}"$(tput sgr0) "- "; }


# Prints "done" and any given arguments with a new line.
ready() { echo $(tput setaf 2)"done"$@$(tput sgr0); }


create_swapfile() {
	# Creates a swapfile. 2Gigs in size.
	status_msg
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile >/dev/null 2>&1
	swapon /swapfile
	printf "\\n/swapfile none swap defaults 0 0\\n" >> /etc/fstab
	printf "vm.swappiness=10\\nvm.vfs_cache_pressure=50" > /etc/sysctl.d/99-sysctl.conf
	ready
}


clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
	dotfilesrepo=$1
	status_msg
	local dir=$(mktemp -d)
    chown -R "$name:wheel" "$dir"
    cd $dir
	echo ".cfg" > .gitignore
	sudo -u "$name" git clone -q --bare "$dotfilesrepo" $dir/.cfg
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null 2>&1
    rm .gitignore
	sudo -u "$name" cp -rfT . "/home/$name/"
    cd /tmp
	ready
}


firefox_configs() {
	# Downloads firefox configs. Only useful if you upload your configs on github.
	[ `command -v firefox` ] || return
	[ "$1" ] || return

	status_msg

	if [ ! -d "/home/$name/.mozilla/firefox" ]; then
		mkdir -p "/home/$name/.mozilla/firefox"
		chown -R "$name:wheel" "/home/$name/.mozilla/firefox"
	fi

	local dir=$(mktemp -d)
	chown -R "$name:wheel" "$dir"
	sudo -u "$name" git clone -q --depth 1 "$1" "$dir/gitrepo" &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "/home/$name/.mozilla/firefox" &&
	ready && return

	echo "firefox_configs failed."
}


arduino_groups() {
	# Addes user to groups needed by arduino
	[ `command -v arduino` ] || return

	status_msg
	echo cdc_acm > /etc/modules-load.d/cdc_acm.conf
	sudo -u "$name" groups | grep -q uucp || gpasswd -a $name uucp >/dev/null 2>&1
	sudo -u "$name" groups | grep -q lock || gpasswd -a $name lock >/dev/null 2>&1
	ready
}


agetty_set() {
	# Without any arguments, during log in it auto completes the username (of the given user)
	# With argument "auto", it enables auto login to the user.
	systemctl enable --now gdm >/dev/null 2>&1 && ready " GDM enabled" && return
	status_msg
	local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service
	systemctl daemon-reload >/dev/null 2>&1
	systemctl reenable getty@tty1.service >/dev/null 2>&1
	ready "$1"
}


virtualbox() {
	# If on V/box, removes v/box from the guest and installs guest-utils.
	# If virtualbox is installed, adds user to vboxusers group
	status_msg

	if [[ $(lspci | grep VirtualBox) ]]; then
		printf "Guest -"

		case $lsb_dist in
		arch)
			local g_utils="virtualbox-guest-modules-arch virtualbox-guest-utils xf86-video-vmware"
			pacman -S --noconfirm --needed $g_utils >/dev/null 2>&1

			[ ! -f /usr/bin/virtualbox ] && ready && return
			printf "Removing VirtualBox "
			pacman -Rns --noconfirm virtualbox >/dev/null 2>&1
			pacman -Rns --noconfirm virtualbox-host-modules-arch >/dev/null 2>&1
			pacman -Rns --noconfirm virtualbox-guest-iso >/dev/null 2>&1 
		;;
		*)
			echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0)
			return
		;;
		esac

	elif [ `command -v virtualbox` ]; then
		printf "Host -"
		gpasswd -a $name vboxusers >/dev/null 2>&1
	fi
	ready
}


it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	# Requires dkms
	status_msg
	local workdir="/home/$name/.local/sources"
	sudo -u "$name" mkdir -p "$workdir"
	cd "$workdir"
	sudo -u "$name" git clone -q https://github.com/bbqlinux/it87
	cd it87 || echo "Failed" && return
	make dkms
	modprobe it87
	echo "it87" > /etc/modules-load.d/it87.conf
	ready
}


data() {
	# Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" >> /etc/fstab
}


nvidia_drivers() {
	# Installs proprietery Nvidia drivers for supported distros.
	# Returns with no output, if the installation is in VirutalBox.

	[[ $(lspci | grep VirtualBox) ]] && return
	status_msg

	case $lsb_dist in
	arch)
		pacman -S --noconfirm --needed nvidia nvidia-settings >/dev/null 2>&1
		if grep -q "^\[multilib\]" /etc/pacman.conf; then
			pacman -S --noconfirm --needed lib32-nvidia-utils >/dev/null 2>&1
		fi
		ready 
	;;
	*)
		echo $(tput setaf 1)"Guest is not supported yet."$(tput sgr0) 
		return 
	;;
	esac
}


catalog() {
	# Removes orphan pacakges and makes a list of all installed packages 
	# at ~/.local/Fresh_pack_list used to track new installed /uninstalled packages
	
	status_msg
	[ ! -d /home/"$name"/.local ] && sudo -u "$name" mkdir /home/"$name"/.local

	case $lsb_dist in 
		manjaro | arch)
			pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
			sudo -u "$name" pacman -Qq > /home/"$name"/.local/Fresh_pack_list
	 	;;
		raspbian | ubuntu)
			sudo apt-get clean >/dev/null 2>&1
			sudo apt autoremove >/dev/null 2>&1
			sudo -u "$name" apt list --installed 2> /dev/null |
						> /home/"$name"/.local/Fresh_pack_list
		;;
		*)
			printf $(tput setaf 1)"Distro is not supported yet."$(tput sgr0)
			return
		;;
	esac

	ready
}



[ "$(id -nu)" != "root" ] && read -rp "This script must be run as root." && 
exit

[ "$( hostnamectl | awk -F": " 'NR==1 {print $2}' )" != "archiso" ] &&
read -rp "This script is meant to run on a fresh Archlinux installation." &&
exit

clear

repo=https://raw.githubusercontent.com/ispanos/anergos/master
package_lists="$@"
[ -z "$progs_repo" ] && progs_repo="$repo/programs/"
[ -z "$multi_lib_bool" ] && multi_lib_bool=true
[ -z "$timezone" ] && timezone="Europe/Athens"
[ -z "$lang" ] && lang="en_US.UTF-8"

lsb_dist="$(. /etc/os-release && echo "$ID")"

printf "$(tput setaf 4)Anergos:\nDistribution - $lsb_dist\n\n$(tput sgr0)"

[ -z "$hostname" ] 		&& read -rep $'Enter computer\'s hostname: \n' hostname
[ -z "$name" ] 			&& name=$(get_username)
[ -z "$user_password" ] && user_password="$(get_pass $name)"
# [ -z "$root_password" ] && root_password="$(get_pass root)"

core_arch_install && install_progs "$package_lists"

systemctl enable NetworkManager || networkd_config
printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc

[ -f /usr/bin/docker ] && gpasswd -a $name docker >/dev/null 2>&1
[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# Configurations are picked according to the hostname of the computer.
case $hostname in 
	killua)
		printf "\n\nkillua:\n"
		it87_driver; data; nvidia_drivers; create_swapfile;
		agetty_set; arduino_groups; virtualbox; catalog;
		firefox_configs https://github.com/ispanos/mozzila
		clone_dotfiles https://github.com/ispanos/dotfiles
	;;
	*)
		echo "Unknown hostname"
	;;
esac
