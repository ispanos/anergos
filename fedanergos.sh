#!/usr/bin/env bash
# License: GNU GPLv3

[ -d ~/.local ] && mkdir ~/.local
dnf list installed > ~/.local/Freshiest
sudo dnf clean all
sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 
sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf upgrade -y

sudo dnf copr enable skidnik/i3blocks -y


#cat programs/fedora.i3.csv | grep -vP "^#|^,"  | awk -F, '{print $1 " \\"}'

sudo dnf install \
-y \
atool \
calcurse \
exfat-utils \
git \
fzf \
highlight \
htop \
lsd \
lshw \
mediainfo \
neofetch \
neovim \
nmap \
ntfs-3g \
odt2txt \
p7zip \
sshfs \
tmux \
ufw \
unrar \
vifm \
w3m \
wpa_supplicant \
youtube-dl \
inxi \
glxinfo \
simple-mtpfs \
i3 \
i3blocks \
jq \
xorg-x11-server-Xorg \
xorg-x11-xinit \
xorg-x11-server-utils \
xbacklight \
compton \
xdotool \
dunst \
numlockx \
feh \
maim \
xkb-switch \
libnotify \
gnome-terminal \
playerctl \
galculator \
pcmanfm \
gvfs-afc \
gvfs-gphoto2 \
gvfs-mtp \
gvfs-smb \
xarchiver \
firefox \
hunspell-en \
hunspell-el \
NetworkManager \
nm-connection-editor \
NetworkManager-openconnect \
NetworkManager-openvpn \
NetworkManager-pptp \
NetworkManager-vpnc \
NetworkManager-ssh \
paprefs \
pavucontrol \
polkit-gnome \
liberation-fonts \
gcolor3 \
mpv \
zathura-pdf-poppler \
qt5ct \
transmission-gtk \
libreoffice \
libreoffice-langpack-el \
libreoffice-langpack-en

sudo dnf remove \
-y \
openssh-server

dnf list installed > ~/.local/Fresh

source common.sh
    clone_dotfiles  https://github.com/ispanos/dotfiles
    firefox_configs https://github.com/ispanos/mozzila
    agetty_set
    i3lock_sleep
    it87_driver
    data
    power_to_sleep

[ -f /usr/bin/docker ] && gpasswd -a $name docker >/dev/null 2>&1