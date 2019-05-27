#!/bin/sh

# Arch Bootstraping script
# License: GNU GPLv3

while getopts ":a:r:p:h" o; do case "${o}" in
    h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
    r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
    p) progsfile=${OPTARG} ;;
    a) aurhelper=${OPTARG} ;;
    *) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

# DEFAULTS:
[ -z ${dotfilesrepo+x} ] && dotfilesrepo="https://github.com/ispanos/Yar.git"
[ -z ${progsfile+x} ] && progsfile="https://raw.githubusercontent.com/ispanos/YARBS/master/i3.csv"
[ -z ${aurhelper+x} ] && aurhelper="yay"

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

getuserandpass() { \
    # Prompts user for new username an password.
    name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
    while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$pass1" = "$pass2" ]; do
        unset pass2
        pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done ;}

usercheck() { \
    ! (id -u "$name" >/dev/null) 2>&1 ||
    dialog --colors --title "WARNING" --yesno "The user \`$name\` already exists on this system. Some of the configurations are only meant for fresh Archlinux installations (or Manjaro unconfigured). YARBS can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nYARBS will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <Yes> if you don't mind your settings being overwritten.\\n\\nUse it at your onwn risk.\\n\\nNote also that YARBS will change $name's password to the one you just gave." 17 80
    }

adduserandpass() { \
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2 ;}

refreshkeys() { \
    dialog --infobox "Refreshing Arch Keyring..." 4 40
    pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
    }

newperms() { # Set special sudoers settings for install (or after).
    echo "$* " > /etc/sudoers.d/yarbs
    chmod 440 /etc/sudoers.d/yarbs ;}

serviceinit() { for service in "$@"; do
    dialog --infobox "Enabling \"$service\"..." 4 40
    systemctl enable "$service"
    systemctl start "$service"
    done ;}

systembeepoff() { dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
    rmmod pcspkr
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

resetpulse() { dialog --infobox "Reseting Pulseaudio..." 4 50
    killall pulseaudio
    sudo -n "$name" pulseaudio --start ;}

finalize(){ \
    dialog --infobox "Preparing welcome message..." 4 50
    dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user.\\n\\n.t Yiannis" 12 80
    }

putgitrepo() { # Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading and installing config files..." 4 60
    dir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2" && chown -R "$name:wheel" "$2"
    chown -R "$name:wheel" "$dir"
    sudo -u "$name" git clone --depth 1 "$1" "$dir/gitrepo" >/dev/null 2>&1 &&
    sudo -u "$name" cp -rfT "$dir/gitrepo" "$2"
    }

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
    [ -f "/usr/bin/$1" ] || (
    dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
    cd /tmp || exit
    rm -rf /tmp/"$1"*
    curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
    sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
    cd "$1" &&
    sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
    cd /tmp || return) ;}

maininstall() { # Installs all needed programs from main repo.
    dialog --title "YARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
    }

gitmakeinstall() {
    dir=$(mktemp -d)
    dialog --title "YARBS Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
    git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
    cd "$dir" || exit
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return ;}

aurinstall() { \
    dialog --title "YARBS Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
    echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
    sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
    }

pipinstall() { \
    dialog --title "YARBS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
    command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
    yes | pip install "$1"
    }

installationloop() { \
    ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
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
    done < /tmp/progs.csv ;}


## Personal Extras ##

networkdset(){ \
    # Starts networkd as a network manager and configures ethernet.
    serviceinit systemd-networkd
    networkctl | awk '/ether/ {print "[Match]\nName="$2"\n\n[Network]\nDHCP=ipv4\n\n[DHCP]\nRouteMetric=10"}' > /etc/systemd/network/20-wired.network
    }

killua(){ \
    # Temp_Asus_X370_Prime_pro
    sudo -u "$name" $aurhelper -S --noconfirm it87-dkms-git
    [ -f /usr/lib/depmod.d/it87.conf ] && modprobe it87 && echo "it87" > /etc/modules-load.d/it87.conf
    [ -f /etc/systemd/logind.conf ] && sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
}

multilib() { \
    sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
    pacman --noconfirm --needed -Sy
    pacman -Fy
    pacman -S lib32-nvidia-utils
}

microcodegrub() { \
    # use grub with amd microcode
    pacman -S amd-ucode
    # Sets Grub timer to zero
    sed -i "s/GRUB_TIMEOUT=*.$/GRUB_TIMEOUT=0/g" /etc/default/grub && update-grub
    grub-mkconfig -o /boot/grub/grub.cfg ;}

paccleanhook() {\
# keep only latest 3 versions of packages
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/cleanup.hook << EOF
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
}

###############################################################


# Check if user is root on Arch distro. Install dialog.
pacman -Syu --noconfirm --needed dialog ||  error "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? Are you sure you have an internet connection? Are you sure your Arch keyring is updated?"

# Wellcome
dialog --title "Hello" --msgbox "Welcome to my Bootstrapping Script!\\n\\nThis script will automatically install a minimal i3wm Arch Linux desktop, which I use as my main machine.\\n\\n-Yiannis" 13 65 || error "User exited."

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

manualinstall $aurhelper || error "Failed to install AUR helper."

# Installs packages in $progsfile
installationloop
multilib
progsfile="https://raw.githubusercontent.com/ispanos/YARBS/master/progs.csv"
installationloop
progsfile="https://raw.githubusercontent.com/ispanos/YARBS/master/extras.csv"
installationloop

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name"
# rm -f "/home/$name/README.md" "/home/$name/LICENSE"

# Pulseaudio, if/when initially installed, often needs a restart to work immediately.
[ -f /usr/bin/pulseaudio ] && resetpulse

# Install vim `plugged` plugins.
sudo -u "$name" mkdir -p "/home/$name/.config/nvim/autoload"
curl "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > "/home/$name/.config/nvim/autoload/plug.vim"
dialog --infobox "Installing (neo)vim plugins..." 4 50
(sleep 30 && killall nvim) &
sudo -u "$name" nvim -E -c "PlugUpdate|visual|q|q" >/dev/null 2>&1

# Enable NetworkManager if its installed.
[ -f usr/bin/NetworkManager ] && serviceinit NetworkManager

# Most important command! Get rid of the beep!
systembeepoff

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #YARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"


## Personal Extras ##

# Disable Libreoffice start-up logo
[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# serviceinit fstrim.timer numLockOnTty.service

echo "vm.swappiness=10" >> /etc/sysctl.d/100-sysctl.conf

# Enable infinality fonts
[ -f /etc/profile.d/freetype2.sh ] && sed -i 's/.*export.*/export FREETYPE_PROPERTIES="truetype:interpreter-version=38"/g' /etc/profile.d/freetype2.sh > /etc/profile.d/freetype2.sh

networkdset

killua

# microcodegrub

paccleanhook


# Last message! Install complete!
finalize
clear
