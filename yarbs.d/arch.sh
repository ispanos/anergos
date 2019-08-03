#!/bin/bash
# License: GNU GPLv3
dialog --infobox "Setting up Arch..." 3 20

function systemd_boot() {
	bootctl --path=/boot install >/dev/null 2>&1
	cat > /boot/loader/loader.conf <<-EOF
		default  arch
		console-mode max
		editor   no
	EOF

	id="UUID=$(lsblk --list -fs -o MOUNTPOINT,UUID | grep "^/ " | awk '{print $2}')"
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

function grub_mbr() {
		pacman --noconfirm --needed -S grub >/dev/null 2>&1
		grub_path=$(lsblk --list -fs -o MOUNTPOINT,PATH | grep "^/ " | awk '{print $2}')
		grub-install --target=i386-pc $grub_path >/dev/null 2>&1
		grub-mkconfig -o /boot/grub/grub.cfg
}

function maininstall() {
	dialog --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	pacman --noconfirm --needed -S "$1" > /dev/null 2>&1
}

function aurinstall() {
	dialog  --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	sudo -u "$name" yay -S --noconfirm "$1" >/dev/null 2>&1
}

function gitmakeinstall() {
	dir=$(mktemp -d)
	dialog --infobox "Installing \`$(basename "$1")\` ($n of $total). $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" > /dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return
}

function pipinstall() {
	dialog --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
	yes | pip install "$1"
}


systemctl enable systemd-timesyncd.service
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
printf "${rpwd1}\\n${rpwd1}" | passwd >/dev/null 2>&1
unset rpwd1 rpwd2

# Create User and set password
useradd -m -g wheel -G power -s /bin/bash "$name" > /dev/null 2>&1
echo "$name:$upwd1" | chpasswd
unset upwd1 upwd2

# Dependencies
dialog --title "First things first." --infobox "Installing 'base-devel' and 'git'." 3 40
pacman --noconfirm --needed -S  git base-devel >/dev/null 2>&1
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel


# Install Yay - Requires user.
dialog --infobox "Installing yay..." 4 50
cd /tmp && curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz
sudo -u ${name} tar -xvf yay.tar.gz >/dev/null 2>&1
grep "^MAKEFLAGS" /etc/makepkg.conf >/dev/null 2>&1 || 
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
cd yay && sudo -u ${name} makepkg --needed --noconfirm -si >/dev/null 2>&1
cd /tmp || return


if [ "$multi_lib_bool" ]; then
	dialog --infobox "Enabling multilib..." 0 0
	sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
	pacman --noconfirm --needed -Syu >/dev/null 2>&1
fi

for i in "$@"; do curl -Ls "$repo/programs/$i.csv" | sed '/^#/d' >> /tmp/progs.csv; done

total=$(wc -l < /tmp/progs.csv)
while IFS=, read -r tag program comment; do
	((n++))
	echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && 
	comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
	case "$tag" in
		"")  maininstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		"A") aurinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		"G") gitmakeinstall "$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
		"P") pipinstall 	"$program" "$comment" || echo "$program" >> /home/${name}/failed ;;
	esac
done < /tmp/progs.csv

dialog --infobox "Removing orphans..." 0 0
pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1
sudo -u "$name" mkdir -p /home/"$name"/.local/
pacman -Qq > /home/"$name"/.local/Fresh_pack_list

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

grep "^Color" 	/etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" 	/etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/Color/a ILoveCandy" /etc/pacman.conf

groupadd pacman && gpasswd -a "$name" pacman
echo "%pacman ALL=(ALL) NOPASSWD: /usr/bin/pacman -Syu" > /etc/sudoers.d/pacman
chmod 440 /etc/sudoers.d/pacman