#!/bin/bash

## Script to setup this dotfile deployment. Tested as working on Linux and Azure Shell

here=`pwd`
mkdir -p ${here}/.local/app
mkdir -p ${here}/.local/bin
mkdir -p ${here}/.ssh


## My own personal project for quickly installing github based releases
rm -rf ${here}/.local/app/ghr-installer
git clone https://github.com/zloeber/ghr-installer.git ${here}/.local/app/ghr-installer

dotfiles=(
	".zshrc"
	".gitconfig"
	".tmux.conf.local"
	".zshrc.local"
	".p10k.zsh")

dotpaths=(
	".ssh"
	".oh-my-zsh"
	".tmux"
)

localdotpaths=(
        ".local/bin"
        ".local/app"
)

for dotfile in "${dotfiles[@]}";do
 echo "Linking file: ${here}/${dotfile}"
 ln -sf "${here}/${dotfile}" "${HOME}/${dotfile}"
done

for dotpath in "${dotpaths[@]}";do
 echo "Linking path: ${here}/${dotpath}"
 ln -sf "${here}/${dotpath}" "${HOME}/"
done

for localdotpath in "${localdotpaths[@]}";do
 echo "Linking .local path: ${here}/${localdotpath}"
 ln -sf "${here}/${localdotpath}" "${HOME}/.local"
done

rm -rf $HOME/.asdf
git clone https://github.com/asdf-vm/asdf.git $HOME/.asdf
cd $HOME/.asdf && git checkout "$(git describe --abbrev=0 --tags)"

make -C ${here}/.local/app/ghr-installer install direnv
