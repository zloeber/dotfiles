#!/bin/bash

## Script to setup this dotfile deployment. Tested as working on Linux and Azure Shell

here=`pwd`

mkdir -p ${HOME}/.local/app
mkdir -p ${HOME}/.local/bin
mkdir -p ${HOME}/.ssh

## My own personal project for quickly installing github based releases
rm -rf ${HOME}/.local/app/ghr-installer
git clone https://github.com/zloeber/ghr-installer.git ${HOME}/.local/app/ghr-installer

dotfiles=(
	".zshrc"
	".gitconfig"
	".tmux.conf.local"
	".zshrc.local"
	".p10k.zsh"
	".tool-versions")

dotpaths=(
	".oh-my-zsh"
	".tmux"
)

localdotpaths=(
	"scripts"
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

## install direnv via my own github app installer
make -C ${here}/.local/app/ghr-installer install direnv

## Setup ASDF for app version management
#  Also install the latest version of the binaries for each plugin
#  Using a .tool-versions file in any directory you can use `asdf install` to install those specific versions as well

rm -rf $HOME/.asdf
git clone https://github.com/asdf-vm/asdf.git $HOME/.asdf
cd $HOME/.asdf && git checkout "$(git describe --abbrev=0 --tags)"
asdf=$HOME/.asdf/bin/asdf
for plugin in $(cut -d ' ' -f 1 ${here}/.tool-versions); do
  if ! $asdf plugin-list | grep $plugin > /dev/null; then
    $asdf plugin add $plugin
  fi
done

bash $HOME/.asdf/plugins/nodejs/bin/import-release-team-keyring

$asdf install

echo "Install of dotfiles complete!"
echo ""
echo "Now optionally run: sudo ./sudo_install.sh"
echo "Then change your shell to zsh with: chsh -s zsh ${whoami}"