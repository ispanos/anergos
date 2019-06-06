# Yiannis' Auto-Rice Bootstraping Scripts (YARBS)

This fork is not mean to replace Luke's project. My end goal is for this script to handle my arch installation. It is meant to be executed right after `arch-chroot`.First it collects all needed information and after a final confirmation sets up the following: 
- Sets Timezone
- Clock
- Locale.
- Network configurations
- `systemd-boot`
- and some other extra configutations I like.
When its done, you are left with a fully functional arch installation, with all of your programs and settings.

## Yarbs vs Larbs

As I said earlier, this is not a replacement for Larbs. You need to know yourself how to install arch with `systemd-boot` so you can edit the script and change the parts that will not work for you. 
I'm not an experienced programmer and I'm definately not an advanced shell-script coder, so if anyone want's to condtribute changes I'll be more than glad to accept commits. 

#### Right now it can't really handle LUKS/LVM root partitions. 