#!/bin/bash
# License: GNU GPLv3
# /*
# it87
# bootloader?
# */
hostname=killua
name=yiannis
user_password=
root_password=
multi_lib_bool=
timezone="Europe/Athens"
lang="en_US.UTF-8"
repo=https://raw.githubusercontent.com/ispanos/YARBS/master
dotfilesrepo="https://github.com/ispanos/dotfiles.git"

for i in "$@"; do prog_files="$prog_files $repo/programs/$i.csv"; done

curl -sL "$repo/yarbs.d/get_stuff.sh" 	> /tmp/get_stuff.sh && source /tmp/get_stuff.sh
curl -sL "$repo/yarbs.d/arch.sh" 		> /tmp/arch.sh 		&& source /tmp/arch.sh
curl -sL "$repo/yarbs.d/mpc.sh" 		> /tmp/mpc.sh 		&& source /tmp/mpc.sh

cat > /etc/sudoers.d/wheel <<-EOF
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/loadkeys,\
/usr/bin/systemctl restart systemd-networkd,/usr/bin/systemctl restart systemd-resolved,\
/usr/bin/systemctl restart NetworkManager
EOF
chmod 440 /etc/sudoers.d/wheel