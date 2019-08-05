#!/bin/bash
# License: GNU GPLv3
# /*
# bootloader | objcopy | Preparing kernels for /EFI/Linux
# */
hostname=lol
root_password=lol
timezone="Europe/Athens"
lang="en_US.UTF-8"
repo=https://raw.githubusercontent.com/ispanos/anergos/master

pacman --noconfirm -Sy



function systemd_boot() {
	bootctl --path=/boot install
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
pacman --noconfirm --needed -S ${cpu}-ucode


systemd_boot && pacman --needed --noconfirm -S efibootmgr > /dev/null 2>&1

# Set root password
printf "${root_password}\\n${root_password}" | passwd
unset root_password

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
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd