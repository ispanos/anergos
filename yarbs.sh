#!/bin/sh

# Arch Bootstraping script
# License: GNU GPLv3

dotfilesrepo="https://github.com/ispanos/Yar.git"
progsfiles="https://raw.githubusercontent.com/ispanos/YARBS/master/i3.csv https://raw.githubusercontent.com/ispanos/YARBS/master/progs.csv https://raw.githubusercontent.com/ispanos/YARBS/master/extras.csv"
aurhelper="yay"

# repo/files folder.
vmconfig="https://raw.githubusercontent.com/ispanos/YARBS/master/files/99-sysctl.conf"
paccleanhook="https://raw.githubusercontent.com/ispanos/YARBS/master/files/cleanup.hook"

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

getuserandpass() {
    # Prompts user for new username an password.
    name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
    while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        name=$(dialog --no-cancel \
                --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$pass1" = "$pass2" ]; do
        unset pass2
        pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
}

usercheck() {
    ! (id -u "$name" >/dev/null) 2>&1 ||
    dialog --colors --title "WARNING" \
            --yesno "The user \`$name\` already exists on this system.
                        Abort (<No>) if you don't know what you're doing." 0 0
}

adduserandpass() {
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2
}

refreshkeys() {
    dialog --infobox "Refreshing Arch Keyring..." 4 40
    pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
}

newperms() { # Set special sudoers settings for install (or after).
    echo "$* " > /etc/sudoers.d/yarbs
    chmod 440 /etc/sudoers.d/yarbs
}

serviceinit() { 
    for service in "$@"; do
    dialog --infobox "Enabling \"$service\"..." 4 40
    systemctl enable "$service"
    systemctl start "$service"
    done
}

systembeepoff() { 
    dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
    rmmod pcspkr
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

resetpulse() { 
    dialog --infobox "Reseting Pulseaudio..." 4 50
    killall pulseaudio
    sudo -n "$name" pulseaudio --start
}

putgitrepo() {
    # Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading and installing config files..." 4 60
    dir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2" && chown -R "$name:wheel" "$2"
    chown -R "$name:wheel" "$dir"
    sudo -u "$name" git clone --depth 1 "$1" "$dir/gitrepo" >/dev/null 2>&1 &&
    sudo -u "$name" cp -rfT "$dir/gitrepo" "$2"
}

manualinstall() { 
    # Installs $1 manually if not installed. Used only for AUR helper here.
    [ -f "/usr/bin/$1" ] || (
    dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
    cd /tmp || exit
    rm -rf /tmp/"$1"*
    curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
    sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
    cd "$1" &&
    sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
    cd /tmp || return)
}

maininstall() { # Installs all needed programs from main repo.
    dialog --title "YARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

gitmakeinstall() {
    dir=$(mktemp -d)
    dialog --title "YARBS Installation" \
    --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
    git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
    cd "$dir" || exit
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return
}

aurinstall() {
    dialog --title "YARBS Installation" \
            --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
    echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
    sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
    dialog --title "YARBS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
    command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
    yes | pip install "$1"
}

mergeprogsfiles() {
    rm /tmp/progs.csv
    for list in "$@"; do
    ([ -f "$list" ] && cp "$list" /tmp/progs.csv) || curl -Ls "$list" | sed '/^#/d' >> /tmp/progs.csv 
    done
}

installationloop() {
    total=$(wc -l < /tmp/progs.csv)
    aurinstalled=$(pacman -Qm | awk '{print $1}')
    while IFS=, read -r tag program comment; do
        n=$((n+1))
        echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
        case "$tag" in
            "") maininstall "$program" "$comment" ;;
            "A") aurinstall "$program" "$comment" ;;
            "G") gitmakeinstall "$program" "$comment" ;;
            "P") pipinstall "$program" "$comment" ;;
        esac
    done < /tmp/progs.csv
}

networkdset() {
    # Starts networkd as a network manager and configures ethernet.
    serviceinit systemd-networkd systemd-resolved
    # Sets up ethernet config
    networkctl | awk '/ether/ {print "[Match]\nName="$2"\n\n[Network]\nDHCP=ipv4\n\n[DHCP]\nRouteMetric=10"}' \
                                                                    > /etc/systemd/network/20-wired.network
    # Setus up wireless config
    networkctl | awk '/wlan/ {print "[Match]\nName="$2"\n\n[Network]\nDHCP=ipv4\n\n[DHCP]\nRouteMetric=20"}' \
                                                                    > /etc/systemd/network/25-wireless.network

    # To do:
    # serviceinit wpa_supplicant@"$(networkctl | awk '/wlan/ {print $2}')"
}

killuaset() {

    # Temp_Asus_X370_Prime_pro
    sudo -u "$name" $aurhelper -S --noconfirm it87-dkms-git >/dev/null 2>&1

    [ -f /usr/lib/depmod.d/it87.conf ] && \
    modprobe it87 >/dev/null 2>&1 && echo "it87" > /etc/modules-load.d/it87.conf

    [ -f /etc/systemd/logind.conf ] && \
    sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
}

multilib() {
    sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
    pacman --noconfirm --needed -Sy >/dev/null 2>&1
    pacman -Fy >/dev/null 2>&1
    pacman --noconfirm -S lib32-nvidia-utils >/dev/null 2>&1
}



###############################################################


# Check if user is root on Arch distro. Install dialog.
    pacman -Syu --noconfirm --needed dialog || \
    pacman --noconfirm -Sy archlinux-keyring &&  pacman -Syu --noconfirm --needed dialog || \
    error "Are you sure you are root and have an internet connection? "

# Wellcome
    dialog --title "Hello" --msgbox "Welcome to my Bootstrapping Script.\\n\\n-Yiannis" 13 65 || error "User exited."

# Get and verify username and password.
    getuserandpass || error "User exited."

# Give warning if user already exists.
    usercheck || error "User exited."

# Last chance for user to back out before install.
    dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35 || { clear; exit; }

# The beginning
    adduserandpass || error "Error adding username and/or password."

# Refresh Arch keyrings.
    refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

#Installs basedevel and git
    dialog --title "YARBS Installation" --infobox "Installing \`basedevel\` and \`git\` for installing other software." 5 70
    pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1
    [ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
    newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
    grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
    grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
    sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

#Installs aurhelper
    manualinstall $aurhelper || error "Failed to install AUR helper."

# Merges program lists, if more than one.
    mergeprogsfiles $progsfiles

# Adds multilib repo and installs nvidia 32bit driver.
    multilib
    
# Installs packages in the newly created /tmp/progs.csv file.
    installationloop

# Install the dotfiles in the user's home directory
    putgitrepo "$dotfilesrepo" "/home/$name"
    # rm -f "/home/$name/README.md"

# Pulseaudio, if/when initially installed, often needs a restart to work immediately.
    [ -f /usr/bin/pulseaudio ] && resetpulse

# Install vim `plugged` plugins.
    sudo -u "$name" mkdir -p "/home/$name/.config/nvim/autoload"
    curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > "/home/$name/.config/nvim/autoload/plug.vim"
    dialog --infobox "Installing (neo)vim plugins..." 4 50
    (sleep 30 && killall nvim) &
    sudo -u "$name" nvim -E -c "PlugUpdate|visual|q|q" >/dev/null 2>&1

# Get rid of the beep!
    systembeepoff

# Disable Libreoffice start-up logo
    [ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# serviceinit fstrim.timer numLockOnTty.service

# Sets swappiness and cache pressure for better performance. Stored in files/ folder on repo.
    curl $vmconfig > /etc/sysctl.d/99-sysctl.conf

# Enable infinality fonts
    [ -f /etc/profile.d/freetype2.sh ] && \
    sed -i 's/.*export.*/export FREETYPE_PROPERTIES="truetype:interpreter-version=38"/g' /etc/profile.d/freetype2.sh
# Enable sub-pixel RGB rendering
    sudo -u "$name" mkdir -p "/home/$name/.config/fontconfig/conf.d"
    ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /home/$name/.config/fontconfig/conf.d

# Starts and sets-up networkd
    networkdset

####### Alternatively enable NetworkManager if its installed.
#######[ -f usr/bin/NetworkManager ] && serviceinit NetworkManager

# Killua config, if hostname is killua.
    [ $(hostname) = "killua" ] && killuaset

# Creates pacman hook to keep only the 3 latest versions of packages. Stored in files/ folder on repo.
    mkdir -p /etc/pacman.d/hooks
    curl $paccleanhook > /etc/pacman.d/hooks/cleanup.hook

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyuu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/systemctl restart systemd-networkd"

# Last message! Install complete!
    dialog --title "DONE" --msgbox "Cross your fingers and hope it worked." 12 80
clear
