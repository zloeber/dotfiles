#!/bin/bash
here=`pwd`
dotfiles=(
	".zshrc"
	".gitconfig"
	".ssh"
	".local"
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
