#!/bin/bash
here=`pwd`
mkdir -p ${here}/.local/app
mkdir -p ${here}/.local/bin

rm -rf ${here}/.local/app/ghr-installer
git clone git@github.com:zloeber/ghr-installer.git ${here}/.local/app/ghr-installer

dotfiles=(
	".zshrc"
	".gitconfig"
	".ssh"
	".local/bin"
	".local/app"
	".oh-my-zsh"
	".tmux"
	".tmux.conf.local"
	".zgen"
	".zshrc.local"
	".p10k.zsh")

for dotfile in "${dotfiles[@]}";do
 echo "Linking: ${here}/${dotfile}"
 ln -sf "${here}/${dotfile}" "${HOME}/${dotfile}"
done