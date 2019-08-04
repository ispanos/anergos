#!/bin/bash
# License: GNU GPLv3
# /*
# it87
# bootloader | objcopy | Preparing kernels for /EFI/Linux
# */
hostname=killua
name=test
user_password=test
root_password=test
multi_lib_bool=
timezone="Europe/Athens"
lang="en_US.UTF-8"
dotfilesrepo="https://github.com/ispanos/dotfiles.git"

repo=https://raw.githubusercontent.com/ispanos/anergos/master
curl -sL "$repo/anergos.d/get_stuff.sh" > /tmp/get_stuff.sh && source /tmp/get_stuff.sh
curl -sL "$repo/anergos.d/arch.sh" 		> /tmp/arch.sh 		&& source /tmp/arch.sh
curl -sL "$repo/anergos.d/mpc.sh" 		> /tmp/mpc.sh 		&& source /tmp/mpc.sh