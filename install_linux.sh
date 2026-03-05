#!/bin/bash

# Installer script for Linux (Debian/Ubuntu based)

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update package lists
sudo apt-get update

# Install packages available in apt
sudo apt-get install -y \
    asciinema \
    bat \
    eza \
    kubectx \
    fzf \
    gh \
    jq \
    yq \
    kubectl \
    neovim \
    podman \
    ripgrep \
    software-properties-common \
    stow \
    tmux \
    wget \
    zsh

# --- Packages requiring manual or different installation steps ---

# Create bin directory if it doesn't exist
mkdir -p ~/bin

# Create a temporary directory for downloads
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# gemini-cli
# Instructions: Depends on how it's distributed for Linux. Likely not in apt.
echo "Manual installation needed for gemini-cli."

# git-delta
# Instructions: https://dandavison.github.io/delta/installation.html
echo "Installing git-delta..."
LATEST_DELTA_URL=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-musl.tar.gz$")) | .browser_download_url')
wget $LATEST_DELTA_URL -O git-delta.tar.gz
tar -xzf git-delta.tar.gz
mv $(tar -tf git-delta.tar.gz | head -1 | cut -d/ -f1)/delta ~/bin/delta

# jless
# Instructions: https://github.com/PaulJuliusMartinez/jless?tab=readme-ov-file#installation
echo "Installing jless..."
LATEST_JLESS_URL=$(curl -s https://api.github.com/repos/PaulJuliusMartinez/jless/releases/latest | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-musl.tar.gz$")) | .browser_download_url')
wget $LATEST_JLESS_URL -O jless.tar.gz
tar -xzf jless.tar.gz
mv jless ~/bin/jless

# k9s
# Instructions: https://k9scli.io/topics/install/
echo "Installing k9s..."
wget https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz -O k9s.tar.gz
tar -xzf k9s.tar.gz
mv k9s ~/bin/k9s

# lazygit
# Instructions: https://github.com/jesseduffield/lazygit?tab=readme-ov-file#installation
echo "Installing lazygit..."
LATEST_LAZYGIT_URL=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.assets[] | select(.name | test("Linux_x86_64.tar.gz$")) | .browser_download_url')
wget $LATEST_LAZYGIT_URL -O lazygit.tar.gz
tar -xzf lazygit.tar.gz
mv lazygit ~/bin/lazygit

# lima (Linux VMs on macOS - Not applicable for Linux hosts)
echo "Skipping lima - Not applicable for Linux hosts."

# tpm (Tmux Plugin Manager)
if [ ! -d ~/.tmux/plugins/tpm ]; then
    echo "Installing tpm..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
    echo "tpm already installed."
fi

# Zsh plugins & Theme
# These are often managed by Zsh frameworks (like Oh My Zsh) or installed manually to ~/.oh-my-zsh/custom or similar
echo "Zsh plugins (fzf-tab, zsh-autocomplete, zsh-autosuggestions, zsh-completions, zsh-syntax-highlighting) and powerlevel10k theme usually require manual setup or a Zsh framework on Linux."

# et (Eternal Terminal)
# Instructions: https://github.com/MisterTea/EternalTerminal#installation
# Skipping et installation as the PPA seems to be broken.
# sudo add-apt-repository ppa:dsm/et -y
# sudo apt-get update
# sudo apt-get install et -y

# Cleanup temporary directory
cd ~
rm -rf $TEMP_DIR

# Nerd Fonts
echo "Manual installation needed for Nerd Fonts. Download from: https://www.nerdfonts.com/font-downloads"

# gcloud-cli
# Instructions: https://cloud.google.com/sdk/docs/install
echo "Manual installation needed for gcloud-cli. Please see: https://cloud.google.com/sdk/docs/install"

# VSCode Extensions - Install via VSCode UI or code command
echo "Install VSCode extensions: github.copilot-chat, ms-azuretools.vscode-containers using the VSCode UI or the 'code --install-extension' command."

echo "Linux installation script finished."
