#!/bin/bash

pacman --needed --noconfirm -S arduino arduino-docs
gpasswd -a yiannis uucp
gpasswd -a yiannis lock


cat > /etc/modules-load.d/cdc_acm.conf <<-EOF
	# https://wiki.archlinux.org/index.php/Arduino
	# Load cdc_acm module for arduino
	cdc_acm
EOF