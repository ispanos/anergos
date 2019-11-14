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
    sudo -u "$name" yay -S --noconfirm --needed $(cat /tmp/progs.csv | sed '/^#/d;/^,/d;s/,.*$//' | tr "\n" " ")
}