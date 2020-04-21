#!/bin/bash

## Script to setup this dotfile deployment. Minimal deployment (sort of)

## install githubapp, direnv, asdf, and xpanes
sudo apt install -y \
  make automake autoconf libreadline-dev unzip curl tmux

make .dep/direnv .dep/xpanes

here=`pwd`

dotfiles=(
	".bash_aliases"
	".profile"
)

for dotfile in "${dotfiles[@]}";do
  if [ -f "${HOME}/${dotfile}" ] ; then
	echo "${HOME}/${dotfile} -> Already exists, removing first (press any key to continue, Ctrl+C to abort!)"
	read
	rm "${HOME}/${dotfile}"
  fi
  echo "Soft linking file: ${here}/${dotfile}"
  ln -sf ${here}/${dotfile} "${HOME}/${dotfile}"
done

echo "Install of dotfiles complete!"
echo "Logout of your shell and back in again to complete this process."
