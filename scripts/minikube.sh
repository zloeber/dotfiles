#!/bin/bash
# Work around script to get minikube running on Ubuntu 19.10
# - Updates local firewall settings (ufw)
# - Whacks your local ./.kube and ./.minikube folders!
# - Runs sudo commands to get things running but does not require sudo to run thereafter

export MINIKUBE_WANTUPDATENOTIFICATION=false
export MINIKUBE_WANTREPORTERRORPROMPT=false
export MINIKUBE_HOME=$HOME
export CHANGE_MINIKUBE_NONE_USER=true
export KUBECONFIG=$HOME/.kube/config
minikubepath=$(which minikube)
sudo ufw allow in on docker0 && sudo ufw allow out on docker0
sudo ${minikubepath} start --vm-driver none
rm -rf $HOME/.minikube
rm -rf $HOME/.kube
sudo mv /root/.kube /root/.minikube $HOME
sudo chown -R $USER:$USER $HOME/.kube $HOME/.minikube

## Replace the config /root with your home path
OLDPATH='\/root'
NEWPATH=$(echo $HOME | sed 's_/_\\/_g')
sed -i -e "s/$OLDPATH/$NEWPATH/g" $HOME/.kube/config
