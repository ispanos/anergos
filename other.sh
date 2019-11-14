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

install_progs() {
	if [ ! "$1" ]; then
		1>&2 echo "No arguments passed. No exta programs will be installed."
		return 1
	fi

	# Use all cpu cores to compile packages
	sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

	# Merges all csv files in one file. Checks for local files first.
	for file in $@; do
		if [ -r programs/${file}.csv ]; then
			cat programs/${lsb_dist}.${file}.csv >> /tmp/progs.csv
		else
			curl -Ls "${programs_repo}${lsb_dist}.${file}.csv" >> /tmp/progs.csv
		fi
	done

	# Remove comments and empty lines.
	sed -i '/^#/d;/^,/d' /tmp/progs.csv

	# Total number of progs in all lists.
	total=$(wc -l < /tmp/progs.csv)

	fail_msg(){
		[ $program ] &&
		echo "$(tput setaf 1)$program failed$(tput sgr0)" | \
				sudo -u "$name" tee -a /home/${name}/failed
	}

	echo  "Installing packages from csv file(s): $@"

	while IFS=, read -r program comment tag; do ((n++))
		# Removes quotes from the comments.
		echo "$comment" | grep -q "^\".*\"$" && 
			comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"

		# Pretty output with columns.
		printf "%07s %-20s %2s %2s" "[$n""/$total]" "$(basename $program)" - "$comment"

		# the actual installation of packages in csv lists.
		case "$tag" in
			"") printf '\n'
				pacman --noconfirm --needed -S "$program" > /dev/null 2>&1 || fail_msg
			;;
			aur | A) printf "(AUR)\n"
				sudo -u "$name" yay -S --needed --noconfirm "$program" >/dev/null 2>&1 || fail_msg
			;;
			git | G) printf "(GIT)\n"
				local dir=$(mktemp -d)
				git clone --depth 1 "$program" "$dir" > /dev/null 2>&1
				cd "$dir" && make >/dev/null 2>&1
				make install >/dev/null 2>&1 || fail_msg
			;;
			pip | P) printf "(PIP)\n"
				# Installs pip if needed.
				command -v pip || quick_install python-pip
				yes | pip install "$program" || fail_msg
			;;
			flatpak | F) printf "(Flatpak)\n"
			#### DONT USE THIS
				flatpak remote-add --if-not-exists \
					flathub \
					https://flathub.org/repo/flathub.flatpakrepo > /dev/null 2>&1
				flatpak install -y "$program" > /dev/null 2>&1
			;;
		esac
	done < /tmp/progs.csv
}