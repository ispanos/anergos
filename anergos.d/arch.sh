#!/usr/bin/env bash
# License: GNU GPLv3

# Usefull variables for arch.sh
# user_password=
# root_password=
[ -z "$multi_lib_bool" ] 	&& multi_lib_bool=true
[ -z "$timezone" ] 			&& timezone="Europe/Athens"
[ -z "$lang" ] 				&& lang="en_US.UTF-8"

get_hostname() { 
	if [ -z "$hostname" ]; then
	    read -rsep $'Enter computer\'s hostname: \n' hostname
	fi
	}

get_username() { 
	[ -z "$name" ] && read -rsep $'Please enter a name for a user account: \n' name
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		read -rsep $'Name not valid. Start with a letter, use lowercase letters, - or _ : \n' name
	done
	}

get_passwords() {
    if [ -z "$user_password" ]; then
        read -rsep $'Enter a password for $name: \n' user_password
        read -rsep $'Retype ${name}\'s password: \n' check_4_pass
        while ! [ "$user_password" = "$check_4_pass" ]; do unset check_4_pass
            read -rsep $'Passwords didn\'t match. Retype ${name}\'s password: \n' user_password
            read -rsep $'Retype ${name}\'s password: \n' check_4_pass
        done
        unset check_4_pass
    fi

    if [ -z "$root_password" ]; then
        read -rsep $'Enter root\'s password: \n' root_password
        read -rsep $'Retype root user password: \n' check_4_pass
        while ! [ "$root_password" = "$check_4_pass" ]; do unset check_4_pass
            read -rsep $'Passwords didn\'t match. Retype root user password: \n' root_password
            read -rsep $'Retype root user password: \n' check_4_pass
        done
        unset check_4_pass
    fi
	}

set_sane_permitions() {
grep -q "NOPASSWD: ALL" /etc/sudoers.d/wheel || return
cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel
unset root_password user_password timezone lang
echo $(tput setaf 2)"${FUNCNAME[0]} in $0 Done!"$(tput sgr0)
sleep 15
}

systemd_boot() {
	bootctl --path=/boot install >/dev/null 2>&1
	cat > /boot/loader/loader.conf <<-EOF
		default  arch
		console-mode max
		editor   no
	EOF

	local id="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"
	cat > /boot/loader/entries/arch.conf <<-EOF
		title   Arch Linux
		linux   /vmlinuz-linux
		initrd  /${cpu}-ucode.img
		initrd  /initramfs-linux.img
		options root=${id} rw quiet
	EOF
	
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
	}

grub_mbr() {
		pacman --noconfirm --needed -S grub >/dev/null 2>&1
		grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
		grub-install --target=i386-pc $grub_path >/dev/null 2>&1
		grub-mkconfig -o /boot/grub/grub.cfg
	}

core_arch_install() {
	echo "Setting up Arch..."

	systemctl enable systemd-timesyncd.service >/dev/null 2>&1
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

	# Install cpu microcode.
	case $(lscpu | grep Vendor | awk '{print $3}') in
		"GenuineIntel") cpu="intel" ;;
		"AuthenticAMD") cpu="amd" 	;;
	esac
	pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1

	# Install bootloader
	if [ -d "/sys/firmware/efi" ]; then
		systemd_boot && pacman --needed --noconfirm -S efibootmgr > /dev/null 2>&1
	else
		grub_mbr
	fi

	# Set root password
	printf "${root_password}\\n${root_password}" | passwd >/dev/null 2>&1

	# Create User and set passwords
	useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
	echo "$name:$user_password" | chpasswd
	}

pacman_managing() {
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
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf
	# groupadd pacman; gpasswd -a "$name" pacman >/dev/null 2>&1
	# echo "%pacman ALL=(ALL) NOPASSWD: /usr/bin/pacman -Syu" > /etc/sudoers.d/pacman
	# chmod 440 /etc/sudoers.d/pacman
	}

install_devel_yay() {
	echo "Installing - base-devel"
	pacman --noconfirm --needed -S base-devel >/dev/null 2>&1
	echo "Installing - git"
	pacman --noconfirm --needed -S git >/dev/null 2>&1
	# This is needed for using sudo in the rest of the scirpt.
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel 
	chmod 440 /etc/sudoers.d/wheel

	echo "Installing - yay-bin" # Requires user (core_arch_install).
	cd /tmp ; sudo -u "$name" git clone https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1
	cd yay-bin && sudo -u "$name" makepkg -si --noconfirm >/dev/null 2>&1
	}

install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi

	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
	[ "$multi_lib_bool" = true  ] && sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf

	for i in "$@"; do 
		curl -Ls "$repo/programs/$i.csv" | sed '/^#/d' >> /tmp/progs.csv
	done
	total=$(wc -l < /tmp/progs.csv)

	while IFS=, read -r tag program comment; do ((n++))
		echo "$comment" | grep -q "^\".*\"$" && 
		comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		printf "Installing - ($n of $total) - $(basename "$program") - $comment "
		case "$tag" in
			"")  
				pacman --noconfirm --needed -S "$program" > /dev/null 2>&1 ||
				echo "$program" >> /home/${name}/failed
			;;
			"A") 
				printf "(AUR)"
				sudo -u "$name" yay -S --noconfirm "$program" >/dev/null 2>&1 ||
				echo "$program" >> /home/${name}/failed	
			;;
			"G") 
				local dir=$(mktemp -d)
				git clone --depth 1 "$program" "$dir" > /dev/null 2>&1
				cd "$dir" && make >/dev/null 2>&1
				make install >/dev/null 2>&1 ||
				echo "$program" >> /home/${name}/failed 
				cd /tmp
			;;
			"P")
				printf "(pip)"
				command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
				yes | pip install "$program" || echo "$program" >> /home/${name}/failed
			;;
		esac
		echo " "
	done < /tmp/progs.csv
	}

get_hostname
get_username
get_passwords
core_arch_install
pacman_managing
trap set_sane_permitions EXIT
install_devel_yay
install_progs
