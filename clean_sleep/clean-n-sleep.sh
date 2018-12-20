#!/bin/bash
#script location /usr/local/sbin/clean-n-sleep.sh
sudo -u yiannis /usr/bin/trash-empty
rm -r /home/yiannis/.cache/mozilla/firefox/bwjd0hy6.default/cache2/entries/*
rm -r /home/yiannis/.cache/thumbnails/large/*
rm -r /home/yiannis/.cache/thumbnails/normal/*
sync; echo 3 > /proc/sys/vm/drop_caches
swapoff -a
swapon -a
exit
