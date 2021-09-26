#!/bin/bash

luks_label="cryptroot"
key_file="/root/keyfile"

efi_part_number="1"
root_part_number="2"

install_drive="/dev/vda"

partition_drive_UEFI() {
	# Uses fdisk to create an "EFI System" partition  (500M),
	# and a "Linux root" partition.
	# Obviously it erases all data on the device.
	# Pass the /dev device name as argument.
	cat <<-EOF | fdisk --wipe-partitions always $1
		g
		n
		1

		+500M
		t
		1
		n
		2

		
		t
		2
		24
		w
	EOF
}


create_luks_volume(){
    cryptsetup luksFormat --label=$luks_label $1
    cryptsetup luksOpen $1 $luks_label --key-file $key_file
}

# Afer $install_drive is set.
[[ $install_drive == *"nvme"* ]] && install_drive="${install_drive}p"

root_partition="${install_drive}p${root_part_number}"

create_luks_volume $root_partition
