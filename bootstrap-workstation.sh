#!/bin/bash
## Script to setup this dotfile deployment. Tested as working on Linux and Azure Shell
here=`pwd`

sudo apt install -y \
  make automake autoconf libreadline-dev \
  libncurses-dev libssl-dev libyaml-dev \
  libxslt-dev libffi-dev libtool unixodbc-dev \
  unzip curl tmux zsh docker.io

## install githubapp, direnv, asdf, and xpanes
make deps

dotfiles=(
	".zshrc"
	".gitconfig"
	".tmux.conf.local"
	".zshrc.local"
	".p10k.zsh"
	".tool-versions"
	".bash_aliases"
	".profile"
	".direnv"
)

dotpaths=(
	".oh-my-zsh"
	".tmux"
)

localdotpaths=(
	"scripts"
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

for dotpath in "${dotpaths[@]}";do
 echo "Linking path: ${here}/${dotpath}"
 ln -sf "${here}/${dotpath}" "${HOME}/"
done

for localdotpath in "${localdotpaths[@]}";do
 echo "Linking .local path: ${here}/${localdotpath}"
 ln -sf "${here}/${localdotpath}" "${HOME}/.local"
done

## Setup ASDF for app version management
#  Also install the latest version of the binaries for each plugin
#  Using a .tool-versions file in any directory you can use `asdf install` to install those specific versions as well
asdf=$HOME/.asdf/bin/asdf
export PATH="$HOME/.asdf/bin:$PATH"

# Install the asdf plugin for each tool listed in .tool-versions (which is now linked to your home directory)
for plugin in $(cut -d ' ' -f 1 ${here}/.tool-versions); do
  if ! $asdf plugin-list | grep $plugin > /dev/null; then
    $asdf plugin add $plugin
  fi
done

# Work around for nodejs installation issues in asdf
bash $HOME/.asdf/plugins/nodejs/bin/import-release-team-keyring

# Install all versions of tools listed in .tool-versions
$asdf install

# Install xpanes for tmux
wget https://raw.githubusercontent.com/greymd/tmux-xpanes/v4.1.1/bin/xpanes -O ${HOME}/.local/bin/xpanes
chmod +x ${HOME}/.local/bin/xpanes

echo "Install of dotfiles complete!"
echo ""
echo "Now change your shell to zsh with: chsh -s /usr/bin/zsh ${whoami}"
echo ""
echo "Finally, logout of your shell and back in again to complete the process."
