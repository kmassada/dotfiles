#!/bin/bash

# Installer script for Oh My Zsh and related plugins

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  echo "Oh My Zsh already installed."
fi

# Define ZSH_CUSTOM if not already set
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

# Install Powerlevel10k Theme
if [ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
  echo "Installing Powerlevel10k theme..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM}/themes/powerlevel10k
else
  echo "Powerlevel10k theme already installed."
fi

# Install Zsh Plugins

# zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
  echo "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
else
  echo "zsh-autosuggestions already installed."
fi

# zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
  echo "Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
else
  echo "zsh-syntax-highlighting already installed."
fi

# zsh-completions
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ]; then
  echo "Installing zsh-completions..."
  git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions
else
  echo "zsh-completions already installed."
fi

# zsh-autocomplete
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autocomplete" ]; then
  echo "Installing zsh-autocomplete..."
  git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM}/plugins/zsh-autocomplete
else
  echo "zsh-autocomplete already installed."
fi

# fzf-tab
if [ ! -d "${ZSH_CUSTOM}/plugins/fzf-tab" ]; then
  echo "Installing fzf-tab..."
  git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM}/plugins/fzf-tab
else
  echo "fzf-tab already installed."
fi

echo "Zsh plugin installation script finished."
