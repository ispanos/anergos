# Anergos

## Description:
The name Anergos comes from the discontinued Linux distro Antergos and the Greek word "unemployed" (άνεργος). The scripts in this repository serve two purposes.
1. I want to have an easy way to install all the packages and configurations I need for my workflow, quickly and in a reproducible way.
2. Provide a blueprint for anyone who wants to do something similar, without having to write everthing from scratch.

## [Anergos](https://github.com/ispanos/anergos/blob/master/anergos.sh) - The script:
This script is used to install packages and clone my [dotfiles](https://github.com/ispanos/dotfiles) from my github repo, as well as some hardware-specific drivers. 
The packages have to be in a `.csv` file that has a specific name, according to the distro you are running it on. My `.csv` files are in the [programs folder](https://github.com/ispanos/anergos/tree/master/programs).

The name of the files have to follow these schemes in order to be valid:
`<distro-ID>/<name-of-the-list>.csv` or
`<distro-ID>.<name-of-the-list>.csv` or
`<name-of-the-list>.csv`

- `<distro-ID>` is the ID set in `/etc/os-release`. 
	- For [Archlinux](https://www.archlinux.org/) its `arch`
	- For [Manjaro](https://manjaro.org/) its `manjaro`
	- For [Ubuntu](https://ubuntu.com/) its `ubuntu`
	- For [Fedora](https://getfedora.org/) its `fedora`

- `<name-of-the-list>` is the name you want to give to the list.
	This is also the only part of the file's name that needs to be passed as an argument to [anergos.sh](https://github.com/ispanos/anergos/blob/master/anergos.sh).
	For example, lets say you have two lists of packages for Archlinux:
	`arch.gnome.csv` and `arch.gaming.csv`
	```
	bash anergos.sh gnome gaming
	```
	This command will parse all packages in `arch.gnome.csv`, `arch.gaming.csv` and install all of them using [yay](https://github.com/Jguer/yay) (`yay -S --noconfirm --needed`). [yay-bin](https://aur.archlinux.org/packages/yay-bin/) will be installed automatically if `yay` is not installed already.

- `.csv` is the only valid file type. 
	The files need to contain 3 columns: 
	
	 Name in repo | Purpose (description) | Repository
	| ------------- |-------------| -----|
	 package | This is a package | A
	 \# This is a comment. | This line is ignored | A stands for AUR

	Any deviation from this scheme may result in falure.

The `.csv` files can be placed in the same directory as `anergos.sh`, in a folder named `programs/` in the same directory as `anergos.sh` or in a remote repository. The url for that remote repository is set in the `progs_repo` variable in the script.
I've been using [Archlinux](https://www.archlinux.org/) since mid 2019, so this script is mostly tested on Archlinux. Therefore, program lists for other distros found in this repository may be out of date, or completely useless. You should use your own list(s) anyway.

The dotfiles repository is passed as an argument to the function `clone_dotfiles`. They are cloned to a temporary directory and then copied to your user's HOME directory. Any conflicting files will be overwritten. I should also note that I'm using a bare git repository to store my dotfiles to make it easier to manage and back them up. In order to track and commit changes follow [this turorial](https://www.atlassian.com/git/tutorials/dotfiles) to find out more.

After cloning my dotfiles I apply some extra configurations. Some of them are specific to my hardware. You don't have to remove those functions if you want to test the functionality of the script. There are built-in checks to see if those functions are needed.

If you want to test this script in a virtual machine, install Archlinux using `arch_install.sh`, restart, login to your user and run :
```
bash anergos.sh i3 # for most my packages
# or
bash anergos.sh i3testing # to install less packages and see the results faster.
# Don't use sudo.
```

If you want to use this script with your own configs and packages, create your own `.csv` file, replace my dotfiles repo with your own and you're done. Or even better, fork this repository to add more of your configurations so I can see how other people configure their systems.

#### To do:
- Update package lists for other distros like Fedora, Ubuntu and Manjaro.
- agetty_set : Should I just use a Display manager?


## [Arch_install](https://github.com/ispanos/anergos/blob/master/arch_install.sh) 

#### Warning: I can't recommend you use this script because it involves partitioning and formatting a drive to instal Arch on. I have added some failsafes, but I have only tested it a few times in Virtual machines. It works, but you never know.

#### This script shouldn't be considered a tutorial on how to install Archlinux. Please read the [official installation guide](https://wiki.archlinux.org/index.php/Installation_guide).

This is a script I have created to quickly install Archlinux. Right now I've made it work only for UEFI installations, using [systemd-boot](https://wiki.archlinux.org/index.php/Systemd-boot).
The user is asked for a `hostname`, `username` and `user password`.
Un-comment the following line to also set a root password:
```
# root_password="$(get_pass root)"
```
The user is also asked to enable `multilib` or not. 

If you have mounted the two required partitions (`/mnt` and `/mnt/boot`), the script doesn't prompt you to format any drive/partition. However, you must make sure that the new `/` partition is formated, before you initiate the script.

If you haven't mounted those partitions, you will be prompted to choose a drive to partition and format. ALL DATA WILL BE LOST on that drive, so avoid using it this way if you have multiple partitions on that drive and/or data you haven't backed up. For you're own safety, you could unplug all other drives from your system except the one you want to install Archlinux on. Make sure you have a backup of any usefull files on that drive.

After that, the script installs `base`,`base-devel`,`linux` and a few more packages I consider needed, using `pacstrap`. Then using `arch-chroot`, it runs the function `core_arch_install`. I am not going to explain how that works, since you should already know how to install Arch. The contents of that function should be familiar to you.

One last note. In the first few lines I set 2 variables:
```
export timezone="Europe/Athens"
export lang="en_US.UTF-8"
```
You should changes those according to your region.

#### To do:
- Add LUKS/LVM support.
- Prompt user to select `timezone` and `lang` instead of setting them as variables.
- Add systemd-boot entries for `linux-lts`/`linux-zen` if its installed.
- Add proper support for non-UEFI installations.
