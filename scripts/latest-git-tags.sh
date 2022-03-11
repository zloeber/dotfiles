#!/bin/bash
# Use: ./latest-git-tags.sh

WORKSPACE_PATH=${WORKSPACE_PATH:-"./workspace/default"}
CURPATH=$(pwd)
report=()
for module in $MODULE_LIST; do
    cd "${CURPATH}"
    cd "./${WORKSPACE_PATH}/${module}"
    if [[ "$GIT_UPDATE" == "TRUE" ]]; then
        git checkout master || $(echo "Unable to change to master branch for ${module}" && exit 1)
        git pull --all --tags
    fi
    version=$(git tag -l --sort="-v:refname" | head -n 1 || echo "NA")
    if [[ "$version" == "" ]]; then
        version=NA
    fi
    report+=("${module} - ${version:-"NA"}")
done
for value in "${report[@]}"; do
    echo "$value"
done
