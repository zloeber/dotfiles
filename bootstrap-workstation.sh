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
        ".oh-my-zsh"
	".tmux"
	"scripts"
)

# dotpaths=(
# 	".oh-my-zsh"
# 	".tmux"
# )

# localdotpaths=(
# 	"scripts"
# )

function info () {
  printf "[ \033[00;34m..\033[0m ] $1"
}

function infoline () {
  printf "\r[ \033[00;34m-\033[0m ] $1\n"
}

function user () {
  printf "\r[ \033[0;33m?\033[0m ] $1 "
}

function success () {
  printf "\r\033[2K[ \033[00;32mOK\033[0m ] $1\n"
}

function fail () {
  printf "\r\033[2K[\033[0;31mFAIL\033[0m] $1\n"
  echo ''
  exit
}

if [[ "$OSTYPE" == "darwin"* ]] ; then
  _os_name="darwin"
  _os_version=""
  _os_id="darwin"
  readonly _dir=$(dirname "$(readlink "$0" || echo "$(echo "$0" | sed -e 's,\\,/,g')")")

elif [[ "$OSTYPE" == "linux-gnu" ]] || [[ "$OSTYPE" == "linux-musl" ]] ; then
  readonly _dir=$(dirname "$(readlink -f "$0" || echo "$(echo "$0" | sed -e 's,\\,/,g')")")

  if [[ -f /etc/os-release ]] ; then
    source /etc/os-release
    _os_name="$NAME"
    _os_version="$VERSION_ID"
    _os_id="$ID"
    _os_id_like="$ID_LIKE"

  elif type lsb_release >/dev/null 2>&1 ; then
    _os_name=$(lsb_release -si)
    _os_version=$(lsb_release -sr)

  elif [[ -f /etc/lsb-release ]] ; then
    source /etc/lsb-release
    _os_name="$DISTRIB_ID"
    _os_version="$DISTRIB_RELEASE"

  elif [[ -f /etc/debian_version ]] ; then
    _os_name="Debian"
    _os_version=$(cat /etc/debian_version)

  elif [[ -f /etc/redhat-release ]] ; then
    _os_name=$(awk '{print $1}' /etc/redhat-release)
    _os_version=$(awk '{print $4}' /etc/redhat-release)

  elif [[ -f /etc/centos-release ]] ; then
    _os_name=$(awk '{print $1}' /etc/centos-release)
    _os_version=$(awk '{print $4}' /etc/centos-release)

  else
    fail "Apt installer is not available on your system."
  fi
fi

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

# Install OSX packages
if [[ "$_os_name" == "darwin" ]] || \
   [[ "$_os_id" == "darwin" ]] || \
   [[ "$_os_id_like" == "darwin" ]] ; then

  # System tools.
  brew install coreutils gnu-getopt gnu-sed openssl curl bc jq php72 \
  libmaxminddb geoipupdate python rsync

# Install apt packages
elif [[ "$_os_name" == "debian" ]] || \
     [[ "$_os_name" == "ubuntu" ]] || \
     [[ "$_os_id" == "debian" ]] || \
     [[ "$_os_id" == "ubuntu" ]] || \
     [[ "$_os_id_like" == "debian" ]] || \
     [[ "$_os_id_like" == "ubuntu" ]] ; then

  user "Run apt installer (sudo required)? [Y]es to proceed, anything else to skip."
  read -n 1 action
  case "$action" in
    Y )
      infoline 'apt deployment starting...'
      sudo apt-get update
      sudo apt install -y \
        ca-certificates dnsutils gnupg apt-utils openssl \
        bc jq mmdb-bin libmaxminddb0 libmaxminddb-dev python python-pip rsync \
        make automake autoconf libreadline-dev \
        libncurses-dev libssl-dev libyaml-dev \
        libxslt-dev libffi-dev libtool unixodbc-dev \
        git unzip curl tmux zsh nmap
      
      sudo apt-get install -y --reinstall procps

      # curl -sL https://deb.nodesource.com/setup_10.x | sudo bash -
      # sudo npm install -g observatory-cli

      # rm -rf nmap_7.70-2_amd64.deb
      # wget https://nmap.org/dist/nmap-7.70-1.x86_64.rpm
      # sudo alien nmap-7.70-1.x86_64.rpm
      # sudo dpkg -i nmap_7.70-2_amd64.deb
      # rm -rf nmap_7.70-2_amd64.deb
      # rm -rf nmap-7.70-1.x86_64.rpm

      # wget -c https://github.com/maxmind/geoipupdate/releases/download/v4.0.3/geoipupdate_4.0.3_linux_amd64.deb
      # sudo dpkg -i geoipupdate_4.0.3_linux_amd64.deb
      # rm geoipupdate_4.0.3_linux_amd64.deb
      # if [[ -e "/usr/share/GeoIP/GeoLite2-Country.mmdb" ]] ; then
      #   cd 
      #   sudo wget -O /usr/share/GeoIP/GeoLite2-Country.mmdb.gz -c http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz
      #   sudo gzip -d /usr/share/GeoIP/GeoLite2-Country.mmdb.gz
      #   sudo geoipupdate
      # fi
      success 'apt installs complete!'
      ;;
    * )
      infoline "Skipping apt deployments"
      ;;
  esac
fi

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
infoline "Change your shell to zsh (chsh -s /usr/bin/zsh ${whoami}) then logout of your shell and back in again."
