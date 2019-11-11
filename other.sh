#!/usr/bin/env bash
# License: GNU GPLv3

# Prints the name of the parent function or a prettified output.
status_msg() { printf "%-25s %2s" $(tput setaf 4)"${FUNCNAME[1]}"$(tput sgr0) "- "; }

# Prints "done" and any given arguments with a new line.
ready() { echo $(tput setaf 2)"done"$@$(tput sgr0); }

Install_nvim_plugged_plugins() {
	# Not tested.
	status_msg
	sudo -u "$name" mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" \
									> "/home/$name/.config/nvim/autoload/plug.vim"
	(sleep 30 && killall nvim) &
	sudo -u "$name" nvim -E -c "PlugUpdate|visual|q|q" >/dev/null 2>&1
	ready
}

safe_ssh() {
	# Removes password based authentication for ssh
	sed -i '/#PasswordAuthentication/{s/yes/no/;s/^#//}' /etc/ssh/sshd_config
	# systemctl enable --now sshd
}

extra_arch_configs() {
	# Keeps only the latest 3 versions of packages.
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

	# Adds color to pacman and nano.
	sed -i "s/^#Color/Color/;/Color/a ILoveCandy" /etc/pacman.conf
	printf '\ninclude "/usr/share/nano/*.nanorc"\n' >> /etc/nanorc
}

numlockTTY() {
	# Simple script to enable NumLock on ttys.
	status_msg

	cat > /etc/systemd/system/numLockOnTty.service <<-EOF
		[Unit]
		Description=numlockOnTty
		[Service]
		ExecStart=/usr/bin/numlockOnTty
		[Install]
		WantedBy=multi-user.target
	EOF

	cat > /usr/bin/numlockOnTty <<-EOF
		#!/usr/bin/env bash

		for tty in /dev/tty{1..6}
		do
		    /usr/bin/setleds -D +num < "$tty";
		done

	EOF

	chmod +x /usr/bin/numlockOnTty
	systemctl enable --now numLockOnTty >/dev/null 2>&1
	ready
}

office_logo() {
	# Disables Office startup window
	[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc
}

infinality(){
	# Enables infinality fonts.
	[ ! -r /etc/profile.d/freetype2.sh ] && return
	status_msg
	sed -i 's/^#exp/exp/' /etc/profile.d/freetype2.sh
	ready
}
