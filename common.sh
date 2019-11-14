#!/usr/bin/env bash
# License: GNU GPLv3

# Distro agnostic configs.
# Run as a nornal user. #not tested yet.

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
    dotfilesrepo=$1
	local dir=$(mktemp -d)
    sudo chown -R "$USER" "$dir"
    cd $dir
	echo ".cfg" > .gitignore
	git clone -q --bare "$dotfilesrepo" $dir/.cfg
	git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null 2>&1
    rm .gitignore
	cp -rfT . "/home/$USER/"
    cd /tmp
}


firefox_configs() {
	# Downloads firefox configs. Only useful if you upload your configs on github.
	[ `command -v firefox` ] || return
	[ "$1" ] || return
	[ ! -d "/home/$USER/.mozilla/firefox" ] &&
	mkdir -p "/home/$USER/.mozilla/firefox" &&
	sudo chown -R "$USER" "/home/$USER/.mozilla/firefox"
	local dir=$(mktemp -d)
	sudo chown -R "$USER" "$dir"
	git clone -q --depth 1 "$1" "$dir/gitrepo" &&
	cp -rfT "$dir/gitrepo" "/home/$USER/.mozilla/firefox" &&
	return
	echo "firefox_configs failed."
}


agetty_set() {
	local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $USER --noclear %I \$TERM"
	sudo sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service
	sudo systemctl daemon-reload >/dev/null 2>&1
	sudo systemctl reenable getty@tty1.service >/dev/null 2>&1
}


i3lock_sleep() {
	# Creates a systemd service to lock the desktop with i3lock before sleep.
	# Only enables it if sway is not installed and i3lock is.
	[ `command -v i3lock` ] || return
	sudo cat > /etc/systemd/system/SleepLocki3@${USER}.service <<-EOF
		#/etc/systemd/system/
		[Unit]
		Description=Turning i3lock on before sleep
		Before=sleep.target
		[Service]
		User=%I
		Type=forking
		Environment=DISPLAY=:0
		ExecStart=$(command -v i3lock) -e -f -c 000000 -i /home/${USER}/.config/wall.png -t
		ExecStartPost=$(command -v sleep) 1
		[Install]
		WantedBy=sleep.target
	EOF
	[ `command -v sway` ] && return
	sudo systemctl enable --now SleepLocki3@${USER} >/dev/null 2>&1
}

it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	# Requires dkms
	local workdir="/home/$USER/.local/sources"
	mkdir -p "$workdir"
	cd "$workdir"
	git clone -q https://github.com/bbqlinux/it87
	cd it87 || echo "Failed" && return
	sudo make dkms
	sudo modprobe it87
	echo "it87" | sudo tee /etc/modules-load.d/it87.conf
}


data() {
	# Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	sudo mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" | 
		sudo tee -a /etc/fstab >/dev/null 2>&1
}
