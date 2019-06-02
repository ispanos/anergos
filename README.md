# Yiannis' Auto-Rice Bootstraping Scripts (YARBS)

This fork is not mean to replace Luke's project. My end goal is for this script to handle my arch installation. It is meant to be executed after partitioning the drive, formating the `/` (root) partition (and `/home` if it's separate partition). First it collects all needed information and after a final confirmation: 
- formats the `esp` partition (`/boot`)
- mounts it
- installs `base` group
- `chroot`'s
- ...
- installs `systemd-boot` as bootloader
- ...
And when its done you are left with a fully functional arch installation, with all of your programs and setting.

## Yarbs vs Larbs

As I said earlier, this is not a replacement for Larbs. You need to know yourself how to install arch with `systemd-boot` so you can edit the script and change the parts that will not work for you. Once the script is "functional", I would like to add a proper description so anyone can modify it and use it on his own system. I'm not a programmer and I'm definately not an advanced shell-script coder, so if anyone want's to condtribute changes I'll be more than glad to accept commits. 