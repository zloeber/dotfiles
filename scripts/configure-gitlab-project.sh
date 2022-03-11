#!/bin/bash

echo "GITLAB_URL: ${GITLAB_URL}"
#echo "GITLAB_TOKEN: ${GITLAB_TOKEN}"
echo "GITLAB_PROJECT_ID: ${GITLAB_PROJECT_ID}"
echo ''
echo "update gitlabci-terraform deploy key"
# Add the gitlabci-terraform key for read access
curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"id":2044,"title":"gitlabci-terraform","key":"ssh-rsa ${cert_1_raw} gitlabci-terraform","can_push":false}' \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/deploy_keys" || true

echo ''
echo "update hvault-cicd deploy key"
# Add the hvault-cicd key for read/write access
curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    --data '{"id":18747,"title":"hvault-cicd","key":"ssh-rsa ${cert_2_raw} idampxm-vault-cicd","can_push":true}' \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/deploy_keys" || true

echo ''
echo "update project settings"
# Set the project settgins
curl --request PUT --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}?approvals_before_merge=1&build_timeout=3600&only_allow_merge_if_pipeline_succeeds=true&remove_source_branch_after_merge=true&auto_cancel_pending_pipelines=enabled"

echo ''
echo "update merge request settings"
# Set the merge request settings
curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/approvals?approvals_before_merge=1&merge_requests_author_approval=false&merge_requests_disable_committers_approval=true"

echo ''
echo "update protected branch"
# Remove the protected master branch
curl --request DELETE --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_branches/master" || true
# Set the master branch as protected again
curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_branches?name=master&code_owner_approval_required=true&unprotect_access_level=40&merge_access_level=30&push_access_level=0"

echo ''
echo "update protected tags"
# Remove the protected tags rule
curl --request DELETE --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_tags/v*" || true
# Set the protected tags rule
curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header "Content-Type: application/json" \
    "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/protected_tags?name=v*&access_level=40"
