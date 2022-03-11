#!/bin/bash
# Author: Zachary Loeber

## Ignored extensions when filtering release file names
IGNORED_EXT='(tar\.gz\.asc|\.txt|\.tar\.xz|\.asc|\.MD|\.hsm|\+ent\.hsm|\.rpm|\.deb|\.sha256|\.src\.tar\.gz|\.sig|SHA256SUM|\.log|homebrew)'
HASHICORP_IGNORED='(driver|plugin|consul-|docker|helper|atlas-)'

# Scrapes the Hashicorp release endpoint for valid versions
# Usage: get_hashicorp_version <app>
function get_hashicorp_version () {
    local vendorapp="${1?"Usage: $0 app"}"
    # Scrape HTML from release page for binary versions, which are 
    # given as ${binary}_<version>. We just use sed to extract.
    curl -s "https://releases.hashicorp.com/${vendorapp}/" | grep -v -E "${IGNORED_EXT}" | sed -n "s|.*${vendorapp}_\([0-9\.]*\).*|\1|p" | sed -n 2p
}

# Scrapes the Hashicorp release endpoint for valid apps
# Usage: get_hashicorp_apps <app>
function get_hashicorp_apps () {
    # Scrape HTML from release page for binary app names
    # There MUST be a better way to do this one... :)
    curl -s "https://releases.hashicorp.com/" | grep -o '<a .*href=\"/\(.*\)/">' | cut -d/ -f2 | grep -v -E "${HASHICORP_IGNORED}"
}
