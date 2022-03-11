#!/bin/bash
BASE_PATH=${BASE_PATH:-"."}
CONFIG_FILE=${CONFIG_FILE:-"${BASE_PATH}/default.yml"}
WORKSPACE=${WORKSPACE:-"$(${yq} r $CONFIG_FILE 'workspace')"}
PROJECT=${PROJECT:-"$(${yq} r $CONFIG_FILE 'project')"}
REPO_COUNT=$(${yq} r ${CONFIG_FILE} 'repos.*.url' --collect --length)
TARGET_PATH="${BASE_PATH}/${WORKSPACE}/${PROJECT}"
CURRENT_PATH=$(pwd)
echo "BASE_PATH: ${BASE_PATH}"
echo "CONFIG_FILE: ${CONFIG_FILE}"
echo "WORKSPACE: ${WORKSPACE}"
echo "PROJECT: ${PROJECT}"
echo "REPO_COUNT: ${REPO_COUNT}"
echo "CURRENT_PATH: ${CURRENT_PATH}"
mkdir -p "${TARGET_PATH}"

REPO_INDEX=0
while [  $REPO_INDEX -lt $REPO_COUNT ]; do
    cd ${CURRENT_PATH}
    CURRENT_NAME=$(${yq} r $CONFIG_FILE "repos.[$REPO_INDEX].name")
    CURRENT_URL=$(${yq} r $CONFIG_FILE "repos.[$REPO_INDEX].url")
    CLONE_BRANCHES=$(${yq} r $CONFIG_FILE "repos.[$REPO_INDEX].branches.*")
    CLONE_PATH="${TARGET_PATH}/${CURRENT_NAME}"
    echo "CURRENT_NAME: ${CURRENT_NAME}"
    echo "CURRENT_URL: ${CURRENT_URL}"
    echo "CLONE_PATH: ${CLONE_PATH}"
    mkdir -p ${CLONE_PATH}
    git clone --recursive ${CURRENT_URL} ${CLONE_PATH} 2>/dev/null || true
    cd ${CLONE_PATH}
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "none" )
    if [ "${PULL_UPDATES}" != "" ]; then
        echo "Running branch updates"
        for BRANCH in $CLONE_BRANCHES; do
            echo "  Update branch: $BRANCH"
            git checkout $BRANCH
            #git pull --autostash
            git stash
            git pull
            git stash pop
        done
        git checkout $CURRENT_PATH 2>/dev/null
    fi
    let REPO_INDEX=REPO_INDEX+1
    echo ""
done
echo "Workspace Created: ${TARGET_PATH}"