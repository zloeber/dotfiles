#!/usr/bin/env bash
## Script to setup this dotfile deployment. Minimal deployment for my mac (sort of)

function info () {
  printf "[ \033[00;34m..\037[0m ] $1"
}

function infoline () {
  printf "\r[ \033[00;34m-\037[0m ] $1\n"
}

function user () {
  printf "\r[ \033[0;33m?\036[0m ] $1 "
}

function success () {
  printf "\r\033[2K[ \033[00;32mOK\033[0m ] $1\n"
}

function fail () {
  printf "\r\033[2K[\033[0;31mFAIL\033[0m] $1\n"
  echo ''
  exit
}

function warn () {
  printf "\r\033[2K[\033[0;33mWARNING\033[0m] $1\n"
  echo ''
}

osname=$(uname)
export COMMANDLINE_TOOLS="/Library/Developer/CommandLineTools"
export OLD_DOTFILES_BAK="${HOME}/old_dotfiles_bak"
export DICTIONARY_DIR="${HOME}/Library/Spelling"
export DOTFILES_REPO_URL="https://github.com/joshukraine/dotfiles.git"
export DOTFILES_DIR="${HOME}/dotfiles"
export TIME_ZONE="America/Chicago"
export DEFAULT_SHELL="zsh"

PS3="> "

comp=$(scutil --get ComputerName)
host=$(scutil --get LocalHostName)

if [ "$osname" == "Linux" ]; then
  fail "Oops, looks like you're on a Linux machine. Please have a look at
  my Linux Bootstrap script: https://github.com/joshukraine/linux-bootstrap"
  exit 1
elif [ "$osname" != "Darwin" ]; then
  fail "Oops, it looks like you're using a non-UNIX system. This script
only supports Mac. Exiting..."
  exit 1
fi

if [ ! -d "$COMMANDLINE_TOOLS" ]; then
  fail "Apple's command line developer tools must be installed before
running this script. To install them, just run 'xcode-select --install' from
the terminal and then follow the prompts. Once the command line tools have been
installed, you can try running this script again."
  exit 1
fi

sudo -v

# Keep-alive: update existing `sudo` time stamp until bootstrap has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

set -e

infoline "\\nLooks good. Here's what we've got so far.\\n"
printf "Time zone:         ==> [%s]\\n" "$TIME_ZONE"
printf "Default shell:     ==> [%s]\\n" "$DEFAULT_SHELL"

echo
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
  echo "Exiting..."
  exit 1
fi

# System tools.
brew bundle

make .dep/direnv .dep/asdf

here=`pwd`

dotfiles=(
  ".zshrc"
  ".tmux.conf.local"
  ".zshrc.local"
  ".p10k.zsh"
  ".tool-versions"
  ".bash_aliases"
  ".profile"
  ".zprofile"
  ".direnv"
  ".oh-my-zsh"
  ".tmux"
  "scripts"
)

link_files () {
  ln -s $1 $2
  success "linked $1 to $2"
}

install_dotfiles () {
  info 'installing dotfiles'
  local target=( "$@" )

  overwrite_all=false
  backup_all=false
  skip_all=false

  for source in "${target[@]}"
  do
    if [ "$source" != "" ]; then
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
    fi
  done

}

# Install dotfiles
user "Run dotfile symlink process? [Y]es to proceed, anything else to skip."
read -n 1 action
case "$action" in
  Y )
    install_dotfiles "${dotfiles[@]}"
    #install_dotfiles "${dotpath[@]}"
    #install_dotfiles "${localdotpath[@]}"
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
infoline "Change your shell to zsh (chsh -s /bin/zsh) then logout of your shell and back in again."
