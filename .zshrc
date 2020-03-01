# .zshrc

# setup zgen
export ZGEN_DIR="${ZDOTDIR:-$HOME}"/.zgen
[[ -d "$ZGEN_DIR" ]] || git clone https://github.com/tarjoilija/zgen.git --depth=1 "$ZGEN_DIR"
ZGEN_RESET_ON_CHANGE=(
  ${ZDOTDIR:-$HOME}/.zshrc
  ${ZDOTDIR:-$HOME}/.zshrc.local
)
#ZSH="$ZGEN_DIR/robbyrussell/oh-my-zsh-master"
ZGEN_PLUGIN_UPDATE_DAYS=5
source "$ZGEN_DIR/zgen.zsh"

# if the init scipt doesn't exist then get to it!
if ! zgen saved; then
    echo "Creating a zgen save"

    zgen oh-my-zsh
    #zgen clone robbyrussell/oh-my-zsh

    # plugins
    zgen oh-my-zsh plugins/git
    zgen oh-my-zsh plugins/sudo
    zgen oh-my-zsh plugins/docker
    zgen oh-my-zsh plugins/terraform
    zgen oh-my-zsh plugins/command-not-found
    zgen oh-my-zsh plugins/helm
    zgen oh-my-zsh plugins/kubectl
    zgen oh-my-zsh plugins/colored-man-pages
    zgen oh-my-zsh plugins/history

    zgen load zsh-users/zsh-history-substring-search
    zgen load zsh-users/zsh-syntax-highlighting
    zgen load unixorn/autoupdate-zgen
   
     # completions
    zgen load zsh-users/zsh-completions
    zgen load zsh-users/zsh-autosuggestions

    # theme
    zgen load romkatv/powerlevel10k powerlevel10k

    # save all to init script
    zgen save
fi

# Source in customizations here
[[ ! -f "${HOME}/.zshrc.local" ]] || source ${HOME}/.zshrc.local

# Enable Powerlevel10k instant prompt.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block, everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f "${HOME}/.p10k.zsh" ]] || source "${HOME}/.p10k.zsh"

