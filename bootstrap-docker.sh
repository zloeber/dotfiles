#!/bin/zsh

make .dep/direnv .dep/xpanes

here=$(pwd)
set -e

dotfiles=(
	".zshrc"
	".tmux.conf.local"
	".zshrc.local"
	".p10k.zsh"
	".tool-versions"
	".bash_aliases"
	".profile"
	".direnv"
  ".oh-my-zsh"
	".tmux"
	"scripts"
)

for dotfile in "${dotfiles[@]}";do
  if [ -f "${HOME}/${dotfile}" ] ; then
    rm "${HOME}/${dotfile}"
  fi
  echo "Soft linking file: ${here}/${dotfile}"
  ln -sf ${here}/${dotfile} "${HOME}/${dotfile}"
done

echo "Install of dotfiles complete!"
