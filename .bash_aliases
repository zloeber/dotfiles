## Alias to githubapp for installing/updating applications from github, nifty.
if [[ -d ${HOME}/.local/app/ghr-installer ]]; then
    alias githubapp="make --no-print-directory -C ${HOME}/.local/app/ghr-installer"
fi
