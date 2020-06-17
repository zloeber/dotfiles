# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

## Customizations for the PATH
## Path customizations
BIN_PATH=$HOME/.local/bin
NPM_BIN_PATH=$HOME/.npm/bin
KREW_BIN_PATH=$HOME/.krew/bin
ASDF_BIN_PATH=$HOME/.asdf/bin
TINYGO_BIN_PATH=/usr/local/tinygo/bin
CARGO_BIN_PATH=$HOME/.cargo/bin

if [ -d $BIN_PATH ]; then
  PATH="$BIN_PATH:${PATH}"
fi

if [ -d /usr/local/tinygo/bin ]; then
  PATH="${PATH}:/usr/local/tinygo/bin"
fi

if [ -d $KREW_BIN_PATH ]; then
  PATH="${PATH}:$KREW_BIN_PATH"
fi

if [ -d $NPM_BIN_PATH ]; then
  PATH="${PATH}:$NPM_BIN_PATH"
fi

if [ -d $ASDF_BIN_PATH ]; then
  PATH="$ASDF_BIN_PATH:${PATH}"
fi

if [ -d $TINYGO_BIN_PATH ]; then
  PATH="${PATH}:$TINYGO_BIN_PATH"
fi

if [ -d $CARGO_BIN_PATH ]; then
  PATH="${PATH}:$CARGO_BIN_PATH"
fi
export GOPATH=$HOME/go
export GO111MODULE=on

export PATH="${GOPATH}:${PATH}"

# if [ -d $ASDF_BIN_PATH ]; then
#   export GOBIN=$(dirname $(asdf which go))
#   export GOROOT=$(dirname $GOBIN)
# fi
