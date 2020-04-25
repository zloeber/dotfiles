#!/usr/bin/env bash
## Script to setup this dotfile deployment. Tested as working on Linux and Azure Shell
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
)
dotpaths=(
	".oh-my-zsh"
	".tmux"
)
localdotpaths=(
	"scripts"
)

info () {
  printf "[ \033[00;34m..\033[0m ] $1"
}

infoline () {
  printf "\r[ \033[00;34m-\033[0m ] $1\n"
}

user () {
  printf "\r[ \033[0;33m?\033[0m ] $1 "
}

success () {
  printf "\r\033[2K[ \033[00;32mOK\033[0m ] $1\n"
}

fail () {
  printf "\r\033[2K[\033[0;31mFAIL\033[0m] $1\n"
  echo ''
  exit
}

setup_gitconfig () {
  if [ -f .gitconfig.template ]
  then
    infoline 'setup gitconfig'
    git_credential='cache'
    if [ "$(uname -s)" == "Darwin" ]
    then
      git_credential='osxkeychain'
    fi
    user ' - What is your github author name?'
    read -e git_authorname
    user ' - What is your github author email?'
    read -e git_authoremail
    sed -e "s/AUTHORNAME/$git_authorname/g" -e "s/AUTHOREMAIL/$git_authoremail/g" -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" .gitconfig.template > ${HOME}/.gitconfig
    success 'gitconfig'
  fi
}

link_files () {
  ln -s $1 $2
  success "linked $1 to $2"
}

install_dotfiles () {
  DOTFILES=$1
  info 'installing dotfiles'

  overwrite_all=false
  backup_all=false
  skip_all=false

  for source in "${dotfiles[@]}"
  do
    src="${here}/${source}"
    dest="$HOME/$source"
    if [ -h $dest ] || [ -f $dest ] || [ -d $dest ]
    then
      overwrite=false
      backup=false
      skip=false
      if [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]
      then
        user "File already exists: `basename $source`, what do you want to do? [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
        read -n 1 action

        case "$action" in
          o )
            overwrite=true;;
          O )
            overwrite_all=true;;
          b )
            backup=true;;
          B )
            backup_all=true;;
          s )
            skip=true;;
          S )
            skip_all=true;;
          * )
            ;;
        esac
      fi

      if [ "$overwrite" == "true" ] || [ "$overwrite_all" == "true" ]
      then
        rm $dest
        success "removed $dest"
      fi

      if [ "$backup" == "true" ] || [ "$backup_all" == "true" ]
      then
        mv $dest $dest\.backup
        success "moved $dest to $dest.backup"
      fi

      if [ "$skip" == "false" ] && [ "$skip_all" == "false" ]
      then
        link_files $src $HOME
      else
        success "skipped $src"
      fi

    else
      link_files $src $HOME
    fi

  done
}

# Install apt packages
user "Run apt installer (sudo required)? [Y]es to proceed, anything else to skip."
read -n 1 action
case "$action" in
  Y )
    infoline 'apt installs starting'
    sudo apt install -y \
      make automake autoconf libreadline-dev \
      libncurses-dev libssl-dev libyaml-dev \
      libxslt-dev libffi-dev libtool unixodbc-dev \
      git nmap unzip curl tmux zsh #docker.io
    success 'apt installs complete!'
    ;;
  * )
    infoline "Skipping apt deployments"
    ;;
esac

here=`pwd`

## install githubapp (ghr-installer), asdf, xpanes, broot, and other apps that are not so easy to automate
## or are used to automatically install other things.
infoline 'Installing dependencies'
make deps
success 'Dependencies installed!'

# Install .gitconfig
user "Run .gitconfig installer? [Y]es to proceed, anything else to skip."
read -n 1 action
case "$action" in
  Y )
    setup_gitconfig
    ;;
  * )
    infoline "Skipping .gitconfig deployment"
    ;;
esac

# Install dotfiles
user "Run dotfile symlink process? [Y]es to proceed, anything else to skip."
read -n 1 action
case "$action" in
  Y )
    install_dotfiles "$dotfiles"
    install_dotfiles "$dotpath"
    install_dotfiles "$localdotpath"
    ;;
  * )
    infoline "Skipping .gitconfig deployment"
    ;;
esac

## Setup ASDF for app version management
#  Also install the latest version of the binaries for each plugin
#  Using a .tool-versions file in any directory you can use `asdf install` to install those specific versions as well
asdf=$HOME/.asdf/bin/asdf
export PATH="$HOME/.asdf/bin:$PATH"

# Install all versions of tools listed in .tool-versions
user "Install asdf apps (listed in .tool-versions)? [Y]es to proceed, anything else to skip."
read -n 1 action
case "$action" in
  Y )
    infoline 'asdf app deployment starting'
    # Install the asdf plugin for each tool listed in .tool-versions (which is now linked to your home directory)
    for plugin in $(cut -d ' ' -f 1 ${here}/.tool-versions); do
      if ! $asdf plugin-list | grep $plugin > /dev/null; then
        $asdf plugin add $plugin
      fi
    done

    # Work around for nodejs installation issues in asdf
    bash $HOME/.asdf/plugins/nodejs/bin/import-release-team-keyring

    $asdf install
    success 'asdf app deployment complete!'
    ;;
  * )
    infoline "Skipping app installations via asdf."
    ;;
esac

githubapp=${HOME}/.local/app/ghr-installer
user "Install githubapps (listed in githubapp.list)? [I]nstall only, [R]eset install (upgrade), anything else to skip."
read -n 1 action
case "$action" in
  I )
    infoline 'githubapp deployment starting'
    for appname in $(cat ${here}/githubapp.list); do
      make --no-print-directory -C ${githubapp} auto ${appname}
    done
    success 'githubapp deployment complete!'
    ;;
  R )
    infoline 'githubapp deployment starting'
    for appname in $(cat ${here}/githubapp.list); do
      make --no-print-directory -C ${githubapp} reset ${appname}
      make --no-print-directory -C ${githubapp} auto ${appname}
    done
    success 'githubapp deployment (reset/update) complete!'
    ;;
  * )
    infoline "Skipping githubapp installation."
    ;;
esac

infoline ''
success "Process complete!"
echo ""
infoline "Change your shell to zsh (chsh -s /usr/bin/zsh ${whoami}) then logout of your shell and back in again."
