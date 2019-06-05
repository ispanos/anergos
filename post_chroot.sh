#!/bin/sh

# Maybe make that into a dialog miltiple choice?
timezone="Europe/Athens"

gethostname() {
    # Prompts user for hostname.
    hostname=$(dialog --inputbox "Please enter a name for the computer (hostname)." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
    while ! echo "$hostname" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        hostname=$(dialog --no-cancel \
        --inputbox "Hostname not valid. Give a hostname beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
}

# Get and set computers' hostname.
gethostname || error "User exited"


#### Time zone
######## servicein() is in yarbs
serviceinit systemd-timesyncd.service
timedatectl set-timezone $timezone
timedatectl set-ntp true


#### Localization
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen && \
locale-gen

# Set the hostname
hostnamectl set-hostname $hostname
echo "127.0.1.1 ${hostname}.localdomain $hostname"
## /etc/hosts ?

### For LVM, system encryption or RAID,
### modify /etc/mkinitcpio.conf 
### HOOKS=".... . .. . keyboard encrypt lvm2"
###	mkinitcpio -p linux


# Install bootloader.
# replace with sd-boot.sh

###
### Set root password
###