#!/bin/bash

## Script to setup this dotfile deployment. Minimal deployment (sort of)

## install githubapp, direnv, asdf, and xpanes
sudo apt install -y \
  make automake autoconf libreadline-dev \
  unzip curl

make deps

here=`pwd`

dotfiles=(
	".bash_aliases"
)

for dotfile in "${dotfiles[@]}";do
 echo "Linking file: ${here}/${dotfile}"
 ln -sf ${here}/${dotfile} "${HOME}/${dotfile}"
done

echo "Install of dotfiles complete!"
echo "Logout of your shell and back in again to complete this process."
