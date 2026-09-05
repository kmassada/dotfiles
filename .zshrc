# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Disable URL escaping when pasting
DISABLE_MAGIC_FUNCTIONS=true

# OS Detection
OS_NAME=$(uname -s)

# Completion styling (MUST BE BEFORE FZF-TAB)
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:*' fzf-flags --preview-window=right:50%:wrap
zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [ -d $realpath ]; then eza -1 --color=always $realpath; elif [ -f $realpath ]; then cat $realpath; fi'

if [[ "$OS_NAME" == "Darwin" ]]; then
  # macOS specific setup
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  BREW_PREFIX=$(brew --prefix)
  GCLOUD_COMPLETION_PATH="$BREW_PREFIX/share/google-cloud-sdk/completion.zsh.inc"
  GCLOUD_PATH_PATH="$BREW_PREFIX/share/google-cloud-sdk/path.zsh.inc"
  FZF_TAB_PATH="$BREW_PREFIX/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
  AUTOSUGGESTIONS_PATH="$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  SYNTAX_HIGHLIGHTING_PATH="$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  POWERLEVEL10K_PATH="$BREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme"
  ZSH_COMPLETIONS_PATH="$BREW_PREFIX/share/zsh-completions"

  # Setup completions path before compinit
  if [[ -d "$ZSH_COMPLETIONS_PATH" ]]; then
    fpath=("$ZSH_COMPLETIONS_PATH" $fpath)
  fi

  # Initialize compinit BEFORE fzf-tab (regenerates at most once per 24h)
  autoload -Uz compinit
  typeset -g ZCOMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${HOST%%.*}-${ZSH_VERSION}"
  if [[ -s "$ZCOMPDUMP" && "$ZCOMPDUMP" -nt "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
    compinit -C -d "$ZCOMPDUMP"
  else
    compinit -u -d "$ZCOMPDUMP"
  fi

  # Source plugins directly for macOS (order: fzf-tab -> autosuggestions -> syntax-highlighting)
  if [[ -f "$FZF_TAB_PATH" ]]; then source "$FZF_TAB_PATH"; fi
  if [[ -f "$AUTOSUGGESTIONS_PATH" ]]; then source "$AUTOSUGGESTIONS_PATH"; fi
  if [[ -f "$SYNTAX_HIGHLIGHTING_PATH" ]]; then source "$SYNTAX_HIGHLIGHTING_PATH"; fi
  if [[ -f "$POWERLEVEL10K_PATH" ]]; then source "$POWERLEVEL10K_PATH"; fi

  # Podman (macOS VM socket dynamically resolved via TMPDIR)
  if [[ -n "$TMPDIR" ]]; then
    export DOCKER_HOST="unix://${TMPDIR%/}/podman/podman-machine-default-api.sock"
  fi
  export PODMAN_COMPOSE_PROVIDER_NO_MESSAGE=1
elif [[ "$OS_NAME" == "Linux" ]]; then
  # Linux specific setup
  GCLOUD_COMPLETION_PATH="/usr/share/google-cloud-sdk/completion.zsh.inc" # Common path, adjust if needed
  GCLOUD_PATH_PATH="/usr/share/google-cloud-sdk/path.zsh.inc" # Common path, adjust if needed
  ZSH_COMPLETIONS_PATH="/usr/share/zsh/site-functions"

  # Oh My Zsh
  export ZSH="$HOME/.oh-my-zsh"

  ZSH_THEME="powerlevel10k/powerlevel10k"

  # Disable Oh My Zsh auto-updates on shell startup to keep startups instant
  zstyle ':omz:update' mode disabled

  # Setup completions path before OMZ loads
  if [[ -d "$ZSH_COMPLETIONS_PATH" ]]; then
    FPATH=$ZSH_COMPLETIONS_PATH:$FPATH
  fi

  plugins=(
      git
      zsh-completions
      fzf-tab
      zsh-autosuggestions
      zsh-syntax-highlighting
  )

  if [ -d "$ZSH" ]; then
    source $ZSH/oh-my-zsh.sh
  else
    echo "Oh My Zsh not found, skipping OMZ loading."
  fi
fi

# Keybindings (MUST BE BEFORE FZF AND PLUGINS)
bindkey -v

# Change cursor shape for different vi modes
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]]; then
    echo -ne '\e[1 q' # Block cursor for command mode
  else
    echo -ne '\e[5 q' # Beam cursor (blinking) for insert mode
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  zle -K viins # Initiate vi insert mode
  echo -ne '\e[5 q'
}
zle -N zle-line-init

# Set tmux pane title to current directory when idle
precmd() {
  if [[ -n "$TMUX" ]]; then
    # ${PWD##*/} gets just the current directory name
    tmux select-pane -T "${PWD##*/}" 
  fi
}

# Reset cursor to beam before executing a command
# And set tmux pane title to the command
preexec() {
  echo -ne '\e[5 q'
  if [[ -n "$TMUX" ]]; then
    # $1 contains the exact command typed, e.g., "vim ~/.zshrc"
    tmux select-pane -T "$1" 
  fi
}

# Edit command line in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd '^x^e' edit-command-line
bindkey -M viins '^x^e' edit-command-line
export EDITOR='nvim'

# Base Tools
export FZF_DEFAULT_COMMAND="rg --files --hidden --ignore-file \"\$HOME/.rgignore\""
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

source <(fzf --zsh)

# Force **+Tab to use the exact same rules
_fzf_compgen_path() {
  rg --files --hidden --ignore-file "$HOME/.rgignore" "$1"
}


# Tool Autocompletions

# kubectl completion (cached to prevent GKE auth triggers on startup)
if type kubectl &>/dev/null; then
  COMPLETION_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kubectl_completion.zsh"
  if [ ! -f "$COMPLETION_CACHE" ]; then
    mkdir -p "$(dirname "$COMPLETION_CACHE")"
    kubectl completion zsh > "$COMPLETION_CACHE" 2>/dev/null
  fi
  if [ -f "$COMPLETION_CACHE" ]; then
    source "$COMPLETION_CACHE"
  fi
fi


# gcloud
if [[ -f "$GCLOUD_COMPLETION_PATH" ]]; then
  source "$GCLOUD_COMPLETION_PATH"
fi
if [[ -f "$GCLOUD_PATH_PATH" ]]; then
  source "$GCLOUD_PATH_PATH"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# History
HISTSIZE=100000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Change the color of valid commands (currently green)
ZSH_HIGHLIGHT_STYLES[command]='fg=#5FAFAF' 

# Change color for aliases (this will fix your 'ls' command)
ZSH_HIGHLIGHT_STYLES[alias]='fg=#5FAFAF'

# Change color for built-in shell commands (like 'cd' or 'echo')
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#5FAFAF'

# Change color for shell functions
ZSH_HIGHLIGHT_STYLES[function]='fg=#5FAFAF'

# Change color for precommands (like 'sudo')
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#5FAFAF'

# Change color for hashed commands
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#5FAFAF'

# Change the color of unknown/invalid commands (currently orange)
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#8787AF'

# Aliases
alias ls='eza'
alias vim='nvim'
alias c='clear'
source $HOME/.zsh_aliases

# Added by Antigravity

export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# Iterm integration
#test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"


# Source all .zsh files in local/ (private overrides)
if [ -d "$HOME/.local" ]; then
  for file in $HOME/.local/*.zsh(N); do
    if [ -r "$file" ]; then
      source "$file"
    fi
  done
fi
