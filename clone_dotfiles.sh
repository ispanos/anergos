#!/usr/bin/env bash

clone_dotfiles() {
	# Clones dotfiles in the home dir in a very specific way.
	# https://www.atlassian.com/git/tutorials/dotfiles
	[ -z "$dotfilesrepo" ] && return
	status_msg

	local dir=$(mktemp -d)
    chown -R "$name:wheel" "$dir"

    cd $dir
	echo ".cfg" > .gitignore

	sudo -u "$name" git clone -q --bare "$dotfilesrepo" $dir/.cfg
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir checkout
	sudo -u "$name" git --git-dir=$dir/.cfg/ --work-tree=$dir config \
				--local status.showUntrackedFiles no > /dev/null 2>&1
    rm .gitignore
	sudo -u "$name" cp -rfT . "/home/$name/"
    cd /tmp

	ready
}

clone_dotfiles