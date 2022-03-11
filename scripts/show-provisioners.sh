#!/bin/bash
## This assumes the provisoiner workspace path has already been updated

workspace_path=${WORKSPACE_PATH:-"workspace/provisioners"}
cicd_version=${CICD_VERSION:-"v0.1.99"}
current_path=$(pwd)
provisioner_paths=$(find "$workspace_path" -type d -maxdepth 1)
for f in $provisioner_paths; do
    cd "$current_path" || exit
    if [[ (-d "$f") && ("$f" != "$workspace_path") ]]; then
        echo "Current Path: $current_path"
        echo "Processing Path: $f"
        cd "$f" || exit
        echo "Current Path: $(pwd)"
        glab mr list
        read
    fi
done

# cd "$current_path"
