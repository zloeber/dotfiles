#!/usr/bin/env bash

if [[ "$EUID" -ne 0 ]] ; then
  printf "EUID is not equal 0 (no root user)\\n"
  exit 1
fi

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
    fail "Autoinstaller is not available on your system."
  fi
fi

if [[ "$_os_name" == "darwin" ]] || \
   [[ "$_os_id" == "darwin" ]] || \
   [[ "$_os_id_like" == "darwin" ]] ; then

  _tread

  # System tools.
  brew install coreutils gnu-getopt gnu-sed openssl curl bc jq php72 \
  libmaxminddb geoipupdate python rsync

  # Install go.
  wget https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz && \
  tar -xvf go1.13.5.linux-amd64.tar.gz && \
  mv go /usr/lib &&
  ln -s /usr/lib/go/bin/go /usr/bin/go

  brew install node nmap

elif [[ "$_os_name" == "debian" ]] || \
     [[ "$_os_name" == "ubuntu" ]] || \
     [[ "$_os_id" == "debian" ]] || \
     [[ "$_os_id" == "ubuntu" ]] || \
     [[ "$_os_id_like" == "debian" ]] || \
     [[ "$_os_id_like" == "ubuntu" ]] ; then

  _tread

  # VSCode
  curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg                                                                                                                                                   ─╯
  install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
  sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list' 

  apt update && apt upgrade -y

  # Install go.
  wget https://dl.google.com/go/go1.16.4.linux-amd64.tar.gz && \
  tar -xvf go1.16.4.linux-amd64.tar.gz && \
  mv go /usr/lib &&
  ln -s /usr/lib/go/bin/go /usr/bin/go
  rm go1.16.4.linux-amd64.tar.gz

  apt install -y \
    ca-certificates \
    dnsutils \
    gnupg \
    apt-utils \
    unzip \
    openssl \
    curl \
    bc \
    jq \
    python3 \
    python3-pip \
    rsync \
    nodejs \
    code \
    byobu \
    zsh \
    make \
    automake \
    tmux \
    git

  apt install -y --reinstall procps

elif [[ "$_os_name" == "CentOS Linux" ]] || \
     [[ "$_os_id" == "centos" ]] || \
     [[ "$_os_id_like" == "rhel fedora" ]] ; then

  _tread

  # Install curl.
  rpm -Uvh http://www.city-fan.org/ftp/contrib/yum-repo/city-fan.org-release-2-1.rhel7.noarch.rpm && \
  yum-config-manager --enable city-fan.org && \
  yum update -y curl

  # Install go.
  wget https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz && \
  tar -xvf go1.13.5.linux-amd64.tar.gz && \
  mv go /usr/lib &&
  ln -s /usr/lib/go/bin/go /usr/bin/go

  yum install -y ca-certificates bind-utils gnupg unzip openssl \
  bc jq mmdb2 mmdb2-devel libmaxminddb libmaxminddb-devel python python-pip rsync

  # wget -c https://github.com/maxmind/geoipupdate/releases/download/v4.0.3/geoipupdate_4.0.3_linux_amd64.rpm &&
  # rpm -Uvh geoipupdate_4.0.3_linux_amd64.rpm

else

  _bye

fi

cd "${_dir}" && rm -fr "${_tmp}"
