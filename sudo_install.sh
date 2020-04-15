#!/bin/bash

## Basic items used for many adsf plugins among other things
apt install -y \
  automake autoconf libreadline-dev \
  libncurses-dev libssl-dev libyaml-dev \
  libxslt-dev libffi-dev libtool unixodbc-dev \
  unzip curl tmux byobu zsh

## Install docker (ubuntu 18.04)
apt install -y docker.io
