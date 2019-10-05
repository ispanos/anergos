# Yiannis' Auto-Rice Bootstraping Scripts (anergos)

## About this repository.
It's an "one-click" script to handle everything when I want to start fresh. [anergos.sh](https://github.com/ispanos/anergos/blob/master/anergos.sh) contains most, if not all, of the configurations I need. 

## For ArchLinux:
It can be used in the chroot environment of archlinux with just the `base` group installed. In the beginning of the script it checks if the hostname of the computer is "archiso". If so, will be asked for a new hostname, user name, user and root password if those variables are not already set in the script. 

Installs bootloader.
If you are booted in UEFI mode it will set-up [Systemd-boot](https://wiki.archlinux.org/index.php/Systemd-boot), otherwise it will install grub.To keep things simple, `esp` must be at `/boot`. If you want to change that, you'll need to modify the function named "systemd_boot", the pacman hook and anything else that might be needed. The grub option is not tested and should only work on MBR partition tables, avoid using it as is.

It will also set the new hostname and root password, create your new user and install `git`, `base-group` and `yay-bin`.

You can use one or more arguments passed in to `anergos.sh` for every list of packages you want to be installed. Those lists are located in programs/\*.csv and you only need to write the name of the file in the `programs/` folder without the suffix (i.e. `bash anergos.sh i3 gnome` ). For more details about the csv files keep reading. 

For my arch installation I'm using [pre-anergos.sh](https://github.com/ispanos/anergos/blob/master/pre-anergos.sh) to format my hardrive and all arguments are passed to `anergos.sh`. I don't recommend using this script, unless you know what exactly it's doing.

During the arch installation a pacman hook is created to run `paccache -rk3` every time you use pacman, `makepkg.conf` is modified to use all cores, adds color to pacman, enables pacman Easter-egg.

To disable \[multilib\] unset `multi_lib_bool=`. Variables `timezone` and `lang` can also be edited according to your needs. This isn't an arch installer for everyone out-of-the-box. Some compromises like that were made to make the installation process faster for me. 

### About the csv files in the programs/ folder:
The first column is a "tag" that determines how the program is installed, "" (blank) for the main repository, A for via the AUR or G if the program is a git repository that is meant to be make && sudo make installed.

The second column is the name of the program in the repository, or the link to the git repository, and the third comment is a description (should be a verb phrase) that describes the program. During installation, anergos will print out this information in a grammatical sentence. It also doubles as documentation for people who read the csv or who want to install my dotfiles manually. If you include commas in your program descriptions, be sure to include double quotes around the whole description to ensure correct parsing.

Depending on your own build, you may want to tactically order the programs in your programs file. anergos will install from the top to the bottom.

## The rest of the script
Well the whole script is split in self-explanatory functions. I'm not going to explain what each function does here, but I know I should add commends to some parts to make it easier to understand. All of my testing is done on my archlinux system and there may be some bugs even on arch, but especially on other distros. Instead of sending `strout` and `strerr` to /dev/null, you could redirect it to a log file to troubleshoot everything.

(\*) : For `clone_dotfiles` I should note that I'm backing up most of my dotfiles in a public repo. It clones the repo with the `--bare` option, and instead  of a `.git` folder, it uses a `.cfg` folder. This way I can use an alias to manage my dotfiles' repo without interfering with other git folders in the \~/home folder. I got the idea from here: https://www.atlassian.com/git/tutorials/dotfiles
This is the alias I have in my .bashrc:

`alias dot='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'`



#### To do: Add LUKS/LVM support && Better description && ( YADM || Stow )

## Disclaimer: 
#### Some may think that this is like a distro based on ArchLinux. NO. This is just a bash scrip that I made for me, but I made it as flexible as I could. Contributions that could make the script more flexible, (like automatically picking up the timezone, or LVM/LUKS support) are more than welcome. I made it this way to make it easy and fast for me. The recommended way to use this script is to fork this repo add a csv file with all the programs you want and keep/add/remove any parts you want. To test it in a VM just download [pre-anergossh](https://github.com/ispanos/anergos/blob/master/pre-anergos.sh) and run `bash pre-anergos.sh i3` or `bash pre-anergos.sh i3testing` to see if you like the way it works.

##### If you are not familiar with installing archlinux the recommended way, I would suggest you not to use this script. Besides the fact that I may break something in the script at any moment, you need to understand how things work and how your system is set-up. E.g. For UEFI installations I'm using `systemd-boot` and not the more traditional `GRUB 2`. This is not a script you are supposed to use as is. Download it offline or make a fork and adjust it to your needs or test it in a VM. 