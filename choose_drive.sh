#!/bin/bash

drive_list_vert=$(/usr/bin/ls -1 /dev | grep "sd.$" && /usr/bin/ls -1 /dev | grep "nvme.$")

list_hard_drives(){
    # All mounted partitions in one line, numbered, separated by a space to make the menu list for dialog
    for i in $drive_list_vert ; do
        local -i n+=1
        printf " $n $i"
    done
}

hard_drive_num=$(dialog --title "Select your Hard-drive" --menu "$(lsblk)" 0 0 0 $(list_hard_drives) 3>&1 1>&2 2>&3 3>&1)

hard_drive="/dev/"$( echo $drive_list_vert | tr " " "\n" | sed -n ${hard_drive_num}p)
#hard_drive=/dev/${hard_drive}
echo $hard_drive