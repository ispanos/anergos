#!/usr/bin/env bash
# License: GNU GPLv3

# distro agnostic configs.

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# Use the alias suggested in the following article.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$1" ] && return
    dotfilesrepo=$1
	local dir=$(mktemp -d)
    chown -R "$name:wheel" "$dir"

    cd $dir
	echo ".cfg" > .gitignore

	sudo -u "$name" git clone -q --bare "$dotfilesrepo" $dir/.cfg
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null 2>&1
    rm .gitignore
	sudo -u "$name" cp -rfT . "/home/$name/"
    cd /tmp
}


firefox_configs() {
	# Downloads firefox configs. Only useful if you upload your configs on github.
	[ `command -v firefox` ] || return
	[ -z "$1" ] && return
    moz_repo=$1

	if [ ! -d "/home/$name/.mozilla/firefox" ]; then
		mkdir -p "/home/$name/.mozilla/firefox"
		chown -R "$name:wheel" "/home/$name/.mozilla/firefox"
	fi

	local dir=$(mktemp -d)
	chown -R "$name:wheel" "$dir"
	sudo -u "$name" git clone -q --depth 1 "$moz_repo" "$dir/gitrepo" &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "/home/$name/.mozilla/firefox" &&
	return

	echo "firefox_configs failed."
}


agetty_set() {
	# Without any arguments, during log in it auto completes the username (of the given user)
	# With argument "auto", it enables auto login to the user.


	if [ "$1" = "auto" ]; then
		local log="ExecStart=-\/sbin\/agetty --autologin $name --noclear %I \$TERM"
	else
		local log="ExecStart=-\/sbin\/agetty --skip-login --login-options $name --noclear %I \$TERM"
	fi

	sed "s/ExecStart=.*/${log}/" /usr/lib/systemd/system/getty@.service > \
								/etc/systemd/system/getty@.service

	systemctl daemon-reload >/dev/null 2>&1
	systemctl reenable getty@tty1.service >/dev/null 2>&1
}


i3lock_sleep() {
	# Creates a systemd service to lock the desktop with i3lock before sleep.
	# Only enables it if sway is not installed and i3lock is.
	status_msg
	cat > /etc/systemd/system/SleepLocki3@${name}.service <<-EOF
		#/etc/systemd/system/
		[Unit]
		Description=Turning i3lock on before sleep
		Before=sleep.target
		[Service]
		User=%I
		Type=forking
		Environment=DISPLAY=:0
		ExecStart=$(command -v i3lock) -e -f -c 000000 -i /home/${name}/.config/wall.png -t
		ExecStartPost=$(command -v sleep) 1
		[Install]
		WantedBy=sleep.target
	EOF

	[ `command -v sway` ] && ready && return
	[ `command -v i3lock` ] &&
	systemctl enable --now SleepLocki3@${name} >/dev/null 2>&1
	ready
}

it87_driver() {
	# Installs driver for many Ryzen's motherboards temperature sensors
	# Requires dkms
	status_msg
	local workdir="/home/$name/.local/sources"
	sudo -u "$name" mkdir -p "$workdir"
	cd "$workdir"
	sudo -u "$name" git clone -q https://github.com/bbqlinux/it87
	cd it87 || echo "Failed" && return
	make dkms
	modprobe it87
	echo "it87" > /etc/modules-load.d/it87.conf
	ready
}


data() {
	# Mounts my HHD. Useless to anyone else
	# Maybe you could use the mount options for your HDD, 
	# or help me improve mine.
	mkdir -p /media/Data || return
	local duuid="UUID=fe8b7dcf-3bae-4441-a4f3-a3111fee8ca4"
	local mntPoint="/media/Data"
	local mntOpt="ext4 rw,noatime,nofail,user,auto 0 2"
	printf "\\n$duuid \t$mntPoint \t$mntOpt\t\\n" >> /etc/fstab
}

power_to_sleep() {
	# Chages the power-button on the pc to a sleep button.
	status_msg
	sed -i '/HandlePowerKey/{s/=.*$/=suspend/;s/^#//}' /etc/systemd/logind.conf
	ready
}

