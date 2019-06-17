#!/bin/bash

# Arch Bootstraping script
# License: GNU GPLv3

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

timezone="Europe/Athens"
aurhelper="yay"
coreprogs="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/progs.csv"
extras="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/extras.csv"
i3="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/i3.csv"
gnome="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/gnome.csv"
sway="https://raw.githubusercontent.com/ispanos/YARBS/master/programs/sway.csv"

# Killua fancntrol settings.
fancontrol="https://raw.githubusercontent.com/ispanos/YARBS/master/files/fancontrol"

# Defaults. Can be changed with arguemnts: -m [false] -e [gnome,i3,sway] -d [<link>,<filepath>]
MULTILIB="true"
environment_arg="i3"
arglist=""
dotfilesrepo="https://github.com/ispanos/dotfiles.git"


while getopts ":m:e:d:p:" option; do 
    case "${option}" in
        m) MULTILIB=${OPTARG} ;;
        e) environment_arg=${OPTARG} ;;
        d) dotfilesrepo=${OPTARG} ;;
        p) arglist=${OPTARG} ;;
        *) printf "Invalid option: -%s\\n" "$OPTARG" ;;
    esac 
done

# Sets $environment according to the argument passed after option "-e"
# If no options where set, it defaults to i3.
if [ $environment_arg = "gnome" ]; then
    environment=$gnome
elif [ $environment_arg = "i3" ]; then
    environment=$i3
elif [ $environment_arg = "sway" ];then
    environment=$sway
else
    printf "Invalid environment. Available options are: \\ngnome\\ni3\\nsway" && exit
fi


prog_files="$coreprogs $environment $extras $arglist"



################################################################################################################
######             SYSTEMD-BOOT set-up              ############################################################

getcpu() {
    # Asks user to choose between "intel" and "amd" cpu. <Cancel> doen't install any microcode (later).
    local -i answer

    answer=$(dialog --title "Microcode" \
                    --menu "Warning: Cancel to skip microcode installation.
                            Choose what cpu microcode to install:" 0 0 0 1 "AMD" 2 "Intel" 3>&1 1>&2 2>&3 3>&1)
    
    if [ $answer -eq 1 ]; then
        cpu="amd"
    elif [ $answer -eq 2 ]; then
        cpu="intel"
    else
        cpu="nmc"
    fi

    if [ $cpu = "nmc" ]; then

        dialog  --title "Please Confirm" \
                --yesno "Are you sure you don't want to install any microcode?" 0 0

    else

        dialog  --title "Please Confirm" \
                --yesno "Are you sure you want to install ${cpu}-ucode? (after final confirmation)" 0 0

    fi
}

listpartnumb(){
    # All mounted partitions in one line, numbered, separated by a space to make the menu list for dialog
    for i in $(blkid -o list | awk '{print $1}'| grep "^/") ; do
        local -i n+=1
        printf " $n $i"
    done
}

chooserootpart() {
    # Creates variable `uuidroot`, needed for loader's entry. Only tested non-encrypted partitions.
    local -i rootpartnumber
    local rootpart

    # Outputs the number assigned to selected partition
    rootpartnumber=$(dialog --title "Please select your root partition (UUID needed for systemd-boot).:" \
                            --menu "$(lsblk) " 0 0 0 $(listpartnumb) 3>&1 1>&2 2>&3 3>&1)

    # Exit the process if the user selects <cancel> instead of a partition.
    if [ $? -eq 1 ]; then
        error "You didn't select any partition. Exiting..."
    fi

    # This is the desired partition.
    rootpart=$( blkid -o list | awk '{print $1}'| grep "^/" | tr ' ' '\n' | sed -n ${rootpartnumber}p)

    # This is the UUID=<number>, neeeded for the systemd-boot entry.
    uuidroot=$( blkid $rootpart | tr " " "\n" | grep "^UUID" | tr -d '"' )
    
    dialog --title "Please Confirm" \
            --yesno "Are you sure this \"$rootpart - $uuidroot\" is your root partition UUID?" 0 0
}

######               SYSTEMD-BOOT END               ######
##########################################################

##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||             System wide configs              ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##

serviceinit() { 
    for service in "$@"; do
        dialog --infobox "Enabling \"$service\"..." 4 40
        systemctl enable "$service"
    done
}

gethostname() {
    # Prompts user for hostname.
    hostname=$(dialog --inputbox "Please enter the hostname." 10 60 3>&1 1>&2 2>&3 3>&1) || exit

    while ! echo "$hostname" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        
        hostname=$(dialog --no-cancel \
        --inputbox "Hostname not valid. It must start with a letter. Only lowercase letters, - or _." \
                    10 60 3>&1 1>&2 2>&3 3>&1)
    
    done
}

systembeepoff() { 
    dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
    rmmod pcspkr && echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

enablemultilib() {
    if [ "$MULTILIB" = "true" ]; then
        dialog --infobox "Enabling multilib..." 0 0
        sed -i '/\[multilib]/,+1s/^#//' /etc/pacman.conf
        pacman --noconfirm --needed -Sy >/dev/null 2>&1
        pacman -Fy >/dev/null 2>&1
    fi
}

getrootpass() {
    # Prompts user for new username an password.
    rootpass1=$(dialog --no-cancel --passwordbox "Enter a password for ROOT user." 10 60 3>&1 1>&2 2>&3 3>&1)
    rootpass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    
    while ! [ "$rootpass1" = "$rootpass2" ]; do
        
        unset rootpass2
        rootpass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." \
                                    10 60 3>&1 1>&2 2>&3 3>&1)
        rootpass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)

    done
}

##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||                 User set-up                  ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##



getuserandpass() {
    # Prompts user for new username an password.
    name=$(dialog --inputbox "Now please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit

    while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        
        name=$(dialog --no-cancel \
                --inputbox "Name not valid. It must start with a letter. Use only lowercase letters, - or _" \
                            10 60 3>&1 1>&2 2>&3 3>&1)
    done

    pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    
    while ! [ "$pass1" = "$pass2" ]; do
        
        unset pass2
        pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." \
                                    10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)

    done
}

adduserandpass() {
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2
}

newperms() {
    # Set special sudoers settings for install (or after).
    echo "$* " > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
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

maininstall() { # Installs all needed programs from main repo.
    dialog --title "YARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

gitmakeinstall() {
    dir=$(mktemp -d)
    dialog  --title "YARBS Installation" \
            --infobox "Installing \`$(basename "$1")\` ($n of $total). $(basename "$1") $2" 5 70

    git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
    cd "$dir" || exit
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return
}

aurinstall() {
    dialog  --title "YARBS Installation" \
            --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70

    echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
    sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
    dialog  --title "YARBS Installation" \
            --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
    command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
    yes | pip install "$1"
}

mergeprogsfiles() {
    for list in ${prog_files}; do

        if [ -f "$list" ]; then
            cp "$list" /tmp/progs.csv
        else
            curl -Ls "$list" | sed '/^#/d' >> /tmp/progs.csv
        fi

    done
}

installationloop() {
    mergeprogsfiles 

    total=$(wc -l < /tmp/progs.csv)
    aurinstalled=$(pacman -Qm | awk '{print $1}')
    
    while IFS=, read -r tag program comment; do
        n=$((n+1))
        echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && \
                comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
        case "$tag" in
            "") maininstall "$program" "$comment" ;;
            "A") aurinstall "$program" "$comment" ;;
            "G") gitmakeinstall "$program" "$comment" ;;
            "P") pipinstall "$program" "$comment" ;;
        esac
    done < /tmp/progs.csv
}

installaurhelper() { 
    dialog --infobox "Installing \"${aurhelper}\"..." 4 50
    cd /tmp || exit
    curl -sO "https://aur.archlinux.org/cgit/aur.git/snapshot/${aurhelper}.tar.gz" &&
    sudo -u "$name" tar -xvf ${aurhelper}.tar.gz >/dev/null 2>&1 &&
    cd ${aurhelper} && sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
    cd /tmp || return
}

killuaset() {
    dialog --infobox "Killua........" 0 0
    # Temp_Asus_X370_Prime_pro
    sudo -u "$name" $aurhelper -S --noconfirm it87-dkms-git >/dev/null 2>&1
    [ -f /usr/lib/depmod.d/it87.conf ] && \
    modprobe it87 >/dev/null 2>&1 && echo "it87" > /etc/modules-load.d/it87.conf
    [ -f /etc/systemd/logind.conf ] && \
    sed -i "s/^#HandlePowerKey=poweroff/HandlePowerKey=suspend/g" /etc/systemd/logind.conf
    curl -Ls "$fancontrol" > /etc/fancontrol && serviceinit fancontrol
}

networkdstart() {
    # Starts networkd as a network manager and configures ethernet.
    networkctl | awk '/ether/ {print "[Match]\nName="$2"\n\n[Network]\nDHCP=ipv4\n\n[DHCP]\nRouteMetric=10"}' \
                                                                    > /etc/systemd/network/20-wired.network
    serviceinit systemd-networkd systemd-resolved
}


##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
######                    Inputs                    ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
pacman --noconfirm -Syyu dialog archlinux-keyring >/dev/null 2>&1 || error "Check your internet connection?"

getcpu
while [ $? -eq 1 ] ; do
    getcpu  
done

chooserootpart
while [ $? -eq 1 ] ; do
    chooserootpart
done

gethostname    || error "User exited"
getuserandpass || error "User exited."
getrootpass    || error "User exited."
dialog --title "Here we go" --yesno "Are you sure you wanna do this?" 6 35 || { clear; exit; }



##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||                     Auto                     ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||##
##||||             System wide config               |||###
##|||||||||||||||||||||||||||||||||||||||||||||||||||||###


if [ ! -d "/sys/firmware/efi" ]; then
    error "Please reboot to UEFI mode. "
fi

dialog --infobox "Locale and time-sync..." 0 0
serviceinit systemd-timesyncd.service
ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen && locale-gen > /dev/null 2>&1
echo 'LANG="en_US.UTF-8"' > /etc/locale.conf

dialog --infobox "Configuring network.." 0 0
echo $hostname > /etc/hostname
cat > /etc/hosts <<EOF
#<ip-address>   <hostname.domain.org>    <hostname>
127.0.0.1       localhost.localdomain    localhost
::1             localhost.localdomain    localhost
127.0.1.1       ${hostname}.localdomain  $hostname
EOF


##########################################################
######             SYSTEMD-BOOT set-up              ######
######   For LVM/LUKS modify /etc/mkinitcpio.conf   ######
######   sed for HOOKS="...keyboard encrypt lvm2"   ######
######   umkinitcpio -p linux && linux-lts entry?   ######

# Installs microcode if the cpu is amd or intel.
if [ $cpu != "nmc" ]; then
    dialog --infobox "Installing ${cpu}-ucode..." 0 0
    pacman --noconfirm --needed -S ${cpu}-ucode >/dev/null 2>&1
fi

# Installs systemd-boot to the eps partition
dialog --infobox "Setting-up systemd-boot" 0 0
bootctl --path=/boot install
 
# Creates pacman hook to update systemd-boot after package upgrade.
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/bootctl-update.hook <<EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
EOF
 
# Creates loader.conf. Stored in files/ folder on repo.
cat > /boot/loader/loader.conf <<EOF
default  arch
console-mode max
editor   no
EOF

# Creates loader entry for root partition, using the "linux" kernel
                    echo "title   Arch Linux"           >  /boot/loader/entries/arch.conf 
                    echo "linux   /vmlinuz-linux"       >> /boot/loader/entries/arch.conf 
[ $cpu = "nmc" ] || echo "initrd  /${cpu}-ucode.img"    >> /boot/loader/entries/arch.conf 
                    echo "initrd  /initramfs-linux.img" >> /boot/loader/entries/arch.conf 
                    echo "options root=${uuidroot} rw"  >> /boot/loader/entries/arch.conf 



##########################################################
######            PERFORMANCE-TWEAKS                ######

dialog --infobox "Performance tweaks. (pacman/yay, vm.cofigs)" 0 0

# Creates pacman hook to keep only the 3 latest versions of packages.
cat > /etc/pacman.d/hooks/cleanup.hook <<EOF
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

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf



dialog --infobox "Creating swapfile" 0 0
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
printf "\\n#Swapfile\\n/swapfile none swap defaults 0 0\\n" > /etc/fstab

# Sets swappiness and cache pressure for better performance.
echo "vm.swappiness=10"         > /etc/sysctl.d/99-sysctl.conf
echo "vm.vfs_cache_pressure=50" > /etc/sysctl.d/99-sysctl.conf

# Installs basedevel and git, disables the beep sound.
dialog --title "Installation" --infobox "Installing \`basedevel\` and \`git\` ..." 5 70
pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1

# Enables multilib unless argument "-m false" was set when running yarbs.
enablemultilib
systembeepoff



##|||||||||||||||||||||||||||||||||||||||||||||||||||||###
##||||                 User set-up                  |||###
##|||||||||||||||||||||||||||||||||||||||||||||||||||||###

# Creates user with given password
adduserandpass || error "Error adding username and/or password."

# Temporarily allows user to run sudo without password.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Installs $aurhelper. Requires user.
installaurhelper || error "Failed to install AUR helper."

# Installs packages in the newly created /tmp/progs.csv file.
installationloop

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name"

# Starts networkmanager if its installed, or uses systemd-networkd
[ -f /usr/bin/NetworkManager ] && serviceinit NetworkManager || networkdstart

# If gdm is installed it enables it.
[ -f /usr/bin/gdm ] && serviceinit gdm

# Disable Libreoffice start-up logo
[ -f /etc/libreoffice/sofficerc ] && sed -i 's/Logo=1/Logo=0/g' /etc/libreoffice/sofficerc

# Enable infinality fonts if freetype2 packages is intalled.
[ -f /etc/profile.d/freetype2.sh ] && \
sed -i 's/.*export.*/export FREETYPE_PROPERTIES="truetype:interpreter-version=38"/g' /etc/profile.d/freetype2.sh

# Killua config, if hostname is killua. Requires $aurhelper.
[ $(hostname) = "killua" ] && killuaset

newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,\
/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyuu,/usr/bin/pacman -Syyu,\
/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,\
/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay -Syu,\
/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/systemctl restart systemd-networkd"

#dialog --infobox "Removing orphan packages." 0 0
#pacman --noconfirm -Rns $(pacman -Qtdq) >/dev/null 2>&1

dialog --infobox "Running pacman-optimize." 0 0
pacman-optimize

mkdir -p /home/"$name"/.local/
pacman -Qq > /home/"$name"/.local/Fresh_Install_package_list

printf "${rootpass1}\\n${rootpass1}" | passwd
unset rootpass1 rootpass2

dialog --msgbox "Cross your fingers and hope it worked.\\n\\nPress <Enter> to exit window." 0 0
read -r