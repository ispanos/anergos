# Yiannis' Auto-Rice Bootstraping Scripts (YARBS)

## This is mostly outdated. Full description coming soon.

## About this repository.
Its an "one-click" script to handle everything when I want to start fresh. Packages are located in programs/\*.csv files. Those files have 3 columns.

The first column is a "tag" that determines how the program is installed, "" (blank) for the main repository, A for via the AUR or G if the program is a git repository that is meant to be make && sudo make installed.

The second column is the name of the program in the repository, or the link to the git repository, and the third comment is a description (should be a verb phrase) that describes the program. During installation, YARBS will print out this information in a grammatical sentence. It also doubles as documentation for people who read the csv or who want to install my dotfiles manually. If you include commas in your program descriptions, be sure to include double quotes around the whole description to ensure correct parsing.

Depending on your own build, you may want to tactically order the programs in your programs file. YARBS will install from the top to the bottom.


### Disclaimer: 
#### Some may think that this is like a distro based on ArchLinux. NO. This is just a bash scrip that I made for me, but I made it as flexible as I could. Contributions that could make the script more flexible, (like automatically picking up the timezone, or LVM/LUKS support) are more than welcome.
##### If you are not familiar with installing archlinux the recommended way, I would suggest you not to use this script. Besides the fact that I may break something in the script at any moment, you need to understand how things work and how your system is set-up. E.g. For UEFI installations I'm using `systemd-boot` and not the more traditional `GRUB 2`. This is not a script you are supposed to use as is. Download it offline or make a fork and adjust it to your needs or test it in a VM. 

## [yarbs.sh](https://github.com/ispanos/YARBS/blob/master/yarbs.sh)

Right now I'm using `dialog` to display step of the process and get user input. It looks cool and I get a better idea of how much time is needed while installing the packages. The downside is that it hides any error message that may appear and the code looks a bit ugly because of it. ( Not that I know how to write scripts better. ) 

If you want to streamline the script even further, `autoconf.sh` can be used to pre-set the variables. If all of them are filled, yarbs.sh will not prompt you for any input.

`yarbs.sh` is supposed to run in the chroot environment, right after you've installed the base group using pacstrap and generated the fstab. I'm using functions and splitting things up into separate files, otherwise the script would be 700 lines of bash in one file. I'm calling the other scripts using `source` so that the variables and common functions can work. 

[Systemd-boot](https://wiki.archlinux.org/index.php/Systemd-boot) only works if you are booted in UEFI mode, so the first step is to check, if the folder "/sys/firmware/efi" doesn't exist, it installs grub (MBR/BIOS only). To keep things simple, `esp` must be at `/boot`. If you want to change that, you'll need to modify the function named "systemd_boot", the pacman hook and anything else that might be needed.

- If the variables in `autoconf.sh` are not set, it asks for a username, password, root password, hostname and after a final confirmation the process begins.
- Sets Timezone ( Defaults to "Europe/Athens" - Change `timezone` variable in the script), hwclock, Locale (en_US.UTF-8)
- Configures network.
- Installs bootloader.
- Creates user.
- Enables multilib if `-m` flag is used.
- Installs base-devel and git.
- Installs yay.
- Installs packages (\*)
- Creates a file "\~/.local/Fresh_pack_list" that includes all of the installed packages.

### This are missing here. (arch.sh and mpc.sh)
- Creates a pacman hook to run `paccache -rk3` every time you use pacman, edits  `makepkg.conf` to use all cores, adds color to pacman, enables pacman Easter-egg.
- Creates a 2GB `/swapfile`, `sets swappiness=10`, sets `cache_pressure=50`
- Disables that awful beeps sound.
- Enables `NetworkManager` if it's installed, or configures and enables `systemd-networkd` and `systemd-resolved`
- Enables `gdm` if it's installed, enables infinality fonts, disables start-up logo in libreoffice if its installed.
- Clones dot files repo (\*\*)

(\*) : Using the flag `-p` you can add as many files or links as you want, containing the packages you want to install. ONLY meant for testing.


(\*\*) : Using the flag `-d` you can add the link of your custom dotfiles repository (URL). ONLY meant for testing. I should note that I'm backing up most of my dotfiles in a public repo. It clones the repo with the `--bare` option, and instead  of a `.git` folder, it uses a `.cfg` folder. This way I can use an alias to manage my dotfiles' repo without interfering with other git folders in the \~/home folder. I got the idea from here: https://www.atlassian.com/git/tutorials/dotfiles
This is the alias I have in my .bashrc:

`alias dot='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'`

I'm currently looking into YADM and Stow. 

### killua.sh
My desktop computer's hostname is "killua". I used that as a way to add some extra configurations that I only want on my desktop pc, without the need of an extra configurations later. I moved that part of the script to a different file to make the config script a bit shorter. Avoid setting your hostname as "killua" during the initial set-up. If you have a better idea, please contact me or make a PR. I think hostnames are a good variable to add system-specific configurations. I don't have a second computer, but if I did maybe Ansible would be even better.

#### To do: Add LUKS/LVM support + Better description?
