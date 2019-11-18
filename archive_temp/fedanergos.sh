#!/usr/bin/env bash
# License: GNU GPLv3

if [ $(id -u) = 0 ]; then
   echo "This script changes your user folder and should not be run as root!"
   echo "You may need to enter your password multiple times!"
   exit 1
fi


# System

# Chages the power-button on the pc to a sleep button.
sudo sed -i '/HandlePowerKey/{s/=.*$/=suspend/;s/^#//}' /etc/systemd/logind.conf

[ -d ~/.local ] && mkdir ~/.local
dnf list installed > ~/.local/Freshiest
sudo dnf clean all
sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 
sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf upgrade -y

sudo dnf copr enable skidnik/i3blocks -y

sudo dnf install -y \
flatpak \
$(cat programs/fedora.i3.csv | sed '/^#/d;/^,/d;s/,.*$//' | tr "\n" " ")
sudo dnf remove -y openssh-server
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo


dnf list installed > ~/.local/Fresh

source common.sh
agetty_set; it87_driver; data;

# User settings.
[ -f /usr/bin/docker ] && sudo usermod -aG docker $USER

clone_dotfiles  https://github.com/ispanos/dotfiles
firefox_configs https://github.com/ispanos/mozzila

# Install steam.
# flatpak -y install flathub com.valvesoftware.Steam