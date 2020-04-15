#!/bin/bash

# a script to download a private cert via keyvault.

CERTPATH=${CERTPATH:-"${HOME}/.ssh/cicd_id_rsa"}
SECRETNAME=${SECRETNAME:-"cicd-private-key"}
VAULTNAME=${VAULTNAME}
AZ_TENANT_ID=${AZ_TENANT_ID:-`az account get-access-token --query tenant --output tsv`}
AZ_SUBSCRIPTIONID=${AZ_SUBSCRIPTIONID:-`az account get-access-token --query subscription --output tsv`}

echo "VAULTNAME: ${VAULTNAME}"
echo "AZ_TENANT_ID: ${AZ_TENANT_ID}"
echo "AZ_SUBSCRIPTIONID: ${AZ_SUBSCRIPTIONID}"

get_secret () {
  #echo "Attempting to get secret: $1"
  if [ ! -z "$1" ]; then
    sed -e 's/^"//' -e 's/"$//' <<<$(az keyvault secret show \
        --vault-name ${VAULTNAME} \
        --name "${1}" \
        --subscription ${AZ_SUBSCRIPTIONID} \
        --query "value")
  fi;
}

get_secret_file () {
  if [ ! -z "$1" ] && [ ! -z "$2" ]; then
    echo "Attempting to download certificate: $1"
    get_secret $1 | sed 's/\\n/\
/g' > $2
    chmod 600 $2
    echo "Attempting to generate public cert from private one."
    ssh-keygen -y -f $2 > $2.pub
  else
    echo "Missing either the secret or file name (or both)."
  fi;
}

get_secret_file ${SECRETNAME} ${CERTPATH}