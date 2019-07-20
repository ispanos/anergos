# Yiannis' Auto-Rice Bootstraping Scripts (YARBS)

## About this repo.
This was originally a fork of [Luke's LARBS](https://github.com/LukeSmithxyz/LARBS), but I converted it to an "one-click" script to handle everything when I wanted to start fresh.

My main goal is for this script to do everything I need. However, I would like to keep it somewhat flexible so that other users can use it too (the script itself, not my dot files and list of packages). Contributions that could make the script more flexible, (like automatically picking up the timezone, or LVM/LUKS support) are more than welcome.

## [yarbs.sh](https://github.com/ispanos/YARBS/blob/master/yarbs.sh)

### Disclaimer: 
##### If you are not familiar with installing archlinux the recommended way, I would suggest you not to use this script. Besides the fact that I may break something in the script at any moment, you need to understand how things work and how your system is set-up. E.g. For UEFI installations I'm using `systemd-boot` and not the more traditional `GRUB 2`. 

Right now I'm using `dialog` to display step of the process and get user input. It looks cool and I get a better idea of how much time is needed while installing the packages. The downside is that it hides any error message that may appear and the code looks a bit ugly because of it. ( Not that I know how to write scripts better. ) 

`yarbs.sh` is supposed to run in the chroot environment, right after you've installed the base group using pacstrap and generated the fstab. I'm using functions to split things up and I'm calling all of the at the end. 

[Systemd-boot](https://wiki.archlinux.org/index.php/Systemd-boot) only works if you are booted in UEFI mode, so the first step is to check, if the folder "/sys/firmware/efi" doesn't exist, it installs grub (MBR/BIOS only). To keep things simple, `esp` must be at `/boot`. If you want to change that, you'll need to modify the function named "systemd_boot"

The rest of the script doesn't have an other requirements (AFAIK).
- It asks for a username, password, root password, hostname and after a final confirmation the process begins.
- Installs dialog, base-devel, git and linux-headers
- Sets Timezone ( Defaults to "Europe/Athens" - Change `timezone` variable in the script), hwclock, Locale (en_US.UTF-8)
- Installs bootloader (systemd-boot)
- Creates a pacman hook to run `paccache -rk3` every time you use pacman, edits  `makepkg.conf` to use all cores, adds color to pacman, enables pacman easter-egg.
- Creates a 2GB `/swapfile`, `sets swappiness=10`, sets `cache_pressure=50`
- Disables that awful beeps sound.
- Enables multilib if `-m` flag is used
- Creates user
- Installs yay as an aur helper
- Installs packages (*)
- Clones dot files repo (**)
- Configures network, enables `NetworkManager` if it's installed, or configures and enables `systemd-networkd` and `systemd-resolved`
- Creates a file "\~/.local/Fresh_pack_list" that includes all of the installed packages.
- Enables `gdm` if it's installed, enables infinality fonts, disables start-up logo in libreoffice if its installed.

(\*) : Using the flag `-p` you can add as many files or links as you want, containing the packages you want to install. I'm using a simple csv format like [Luke's](https://github.com/LukeSmithxyz/LARBS#the-progscsv-list)
YARBS will parse the given programs list and install all given programs. Note that the programs file must be a three column .csv.

The first column is a "tag" that determines how the program is installed, "" (blank) for the main repository, A for via the AUR or G if the program is a git repository that is meant to be make && sudo make installed.

The second column is the name of the program in the repository, or the link to the git repository, and the third comment is a description (should be a verb phrase) that describes the program. During installation, YARBS will print out this information in a grammatical sentence. It also doubles as documentation for people who read the csv or who want to install my dotfiles manually.

Depending on your own build, you may want to tactically order the programs in your programs file. YARBS will install from the top to the bottom.

If you include commas in your program descriptions, be sure to include double quotes around the whole description to ensure correct parsing.

(\*\*) : Using the flag `-d` you can add the link of your custom dotfiles repository (URL). I should note that I'm backing up most of my dotfiles in a public repo. It clones the repo with the `--bare` option, and instead  of a `.git` folder, it uses a `.cfg` folder. This way I can use an alias to manage my dotfiles' repo without interfering with other git folders in the \~/home folder. I got the idea from here: https://www.atlassian.com/git/tutorials/dotfiles
This is the alias I have in my .bashrc:

`alias dot='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'`

### function config_killua
My computer's hostname is "killua". I used that as a way to add some extra configurations that I only want on my pc, without the need of an extra script. I moved that part of the script to a different file to make yarbs a bit shorter. Avoid setting your hostname as "killua" during the initial set-up. If you have a better idea, please contact me or make a PR. I don't have a second computer or I would have used Ansible.

## pre-yarbs.sh
While testing the script on virtualbox, I had to find a way to partition, format, mount the partitions and install arch faster. So I ended up with a second script. Don't use it. It will repartition and format your drive. If you want to use it then please help me make it better and more flexible. Perhaps I can add it to yarbs one day.

#### At some point I want to add LUKS/LVM support. And maybe make this description better?
