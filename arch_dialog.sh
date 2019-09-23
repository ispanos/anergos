#!/usr/bin/env bash
# License: GNU GPLv3

[ $1 ] || { 1>&2 echo "No arguments passed. Please read the scripts description." && exit;}

[ -z "$timezone" ] && timezone="Europe/Athens"
[ -z "$lang" ] && lang="en_US.UTF-8"

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

maininstall() {
	dialog --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	pacman --noconfirm --needed -S "$1" > /dev/null 2>&1 || echo "$1" >> /home/${name}/failed
	}

aurinstall() {
	dialog  --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	sudo -u "$name" yay -S --noconfirm "$1" >/dev/null 2>&1 || echo "$1" >> /home/${name}/failed
	}

gitmakeinstall() {
	local dir=$(mktemp -d)
	dialog --infobox "Installing \`$(basename "$1")\` ($n of $total). $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" > /dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return
	}

pipinstall() {
	dialog --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
	yes | pip install "$1" || echo "$1" >> /home/${name}/failed
	}

flatinstall() {
	dialog --infobox "Installing \`$1\` ($n of $total) from flathub. $1 $2" 5 70
	command -v flatpak || pacman -S --noconfirm --needed flatpak >/dev/null 2>&1
	sudo -u "$name" flatpak install flathub -y --noninteractive "$1" >/dev/null 2>&1
	}

set_sane_permitions() {
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

trap set_sane_permitions EXIT

dialog --infobox "Setting up Arch..." 3 20

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

dialog --title "First things first." --infobox "Installing 'base-devel' and 'git'." 3 40
pacman --noconfirm --needed -S  git base-devel >/dev/null 2>&1
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel

sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

# Install Yay - Requires user.
dialog --infobox "Installing yay..." 4 50
cd /tmp ; sudo -u "$name" git clone https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1
cd yay-bin && sudo -u "$name" makepkg -si --noconfirm >/dev/null 2>&1

if [ "$multi_lib_bool" ]; then
	dialog --infobox "Enabling multilib..." 0 0
	sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
	pacman --noconfirm --needed -Syu >/dev/null 2>&1
fi

for i in "$@"; do curl -Ls "$repo/programs/$i.csv" | sed '/^#/d' >> /tmp/progs.csv; done
total=$(wc -l < /tmp/progs.csv)
while IFS=, read -r tag program comment; do ((n++))
	echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && 
	comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
	case "$tag" in
		"")  maininstall 	"$program" "$comment" ;;
		"A") aurinstall 	"$program" "$comment" ;;
		"G") gitmakeinstall "$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		"P") pipinstall 	"$program" "$comment" ;;
	esac
done < /tmp/progs.csv

dialog --infobox "Removing orphans..." 0 0
pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
sudo -u "$name" mkdir /home/"$name"/.local ; pacman -Qq > /home/"$name"/.local/Fresh_pack_list

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
groupadd pacman; gpasswd -a "$name" pacman >/dev/null 2>&1
echo "%pacman ALL=(ALL) NOPASSWD: /usr/bin/pacman -Syu" > /etc/sudoers.d/pacman
chmod 440 /etc/sudoers.d/pacman
