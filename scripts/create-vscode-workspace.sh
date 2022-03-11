#!/bin/bash
# Use: ./create-vscode-workspace.sh > ../umbrella.code-workspace
CONFIG_FILE=${CONFIG_FILE:-"./default.yml"}
WORKSPACE=${WORKSPACE:-$(yq r ${CONFIG_FILE} workspace)}
PROJECT=${PROJECT:-$(yq r ${CONFIG_FILE} project)}
REPO_PATHS=${REPO_PATHS:-$(yq r ${CONFIG_FILE} 'repos.*.name')}
VSCODEWS=$(cat ./scripts/vscode-workspace.tpl)

for wspath in $REPO_PATHS
do
    newpath="./${WORKSPACE}/${PROJECT}/$wspath"
    VSCODEWS=$(echo $VSCODEWS | jq --arg newpath "$newpath" '.folders += [{ "path": $newpath }]')
done

echo $VSCODEWS