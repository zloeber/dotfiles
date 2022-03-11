#!/usr/bin/env bash
# Some example script functions

set -e

VAULT_ADDR=${VAULT_ADDR-"http://127.0.0.1:8200"}
VAULT_ROLE_ID=${VAULT_ROLE_ID-""}
VAULT_SECRET_ID=${VAULT_SECRET_ID-""}
VAULT_CLIENT_TOKEN=${VAULT_CLIENT_TOKEN-""}

token_exists() {
    echo $VAULT_CLIENT_TOKEN
    echo $VAULT_ACCESSOR
    if [ -z "$VAULT_CLIENT_TOKEN" ] || [ -z "$VAULT_ACCESSOR" ]; then
        echo "$0 - Token or accessor does not exist"
        return 1
    else
        echo 0
    fi
}


token_is_valid() {
  echo "Checking token validity"
  token_lookup=$(curl -X POST \
       -H "X-Vault-Token: $VAULT_CLIENT_TOKEN" \
       -w %{http_code} \
       --silent \
       --output /dev/null \
       -d '{"accessor":"'"$VAULT_ACCESSOR"'"}'  \
       $VAULT_ADDR/v1/auth/token/lookup-accessor)
  if [ "$token_lookup" == "200" ]; then
    echo "$0 - Valid token found, exiting"
    return 0
  else
    echo "$0 - Invalid token found"
    return 1
  fi
}

fetch_token_and_accessor() {
    curl -X POST \
     --silent \
     -d '{"role_id":"'"$VAULT_ROLE_ID"'","secret_id":"'"$VAULT_SECRET_ID"'"}' \
     $VAULT_ADDR/v1/auth/approle/login |\
     tee >(jq --raw-output '.auth.accessor' > /tmp/accessor) >(jq --raw-output '.auth.VAULT_CLIENT_TOKEN' > /tmp/VAULT_CLIENT_TOKEN)
}


renew_token() {
  echo "Renewing token"
  curl -X POST \
       --silent \
       -H "X-Vault-Token: $VAULT_CLIENT_TOKEN" \
       $VAULT_ADDR/v1/auth/token/renew-self | jq
}