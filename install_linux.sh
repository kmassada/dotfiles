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

# Create local directory for Zsh settings
mkdir -p ~/local
touch ~/local/init.zsh


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
LATEST_JLESS_TAG=$(curl -s https://api.github.com/repos/PaulJuliusMartinez/jless/releases/latest | jq -r .tag_name)
if [ -z "$LATEST_JLESS_TAG" ] || [ "$LATEST_JLESS_TAG" == "null" ]; then
    echo "Failed to fetch latest jless tag. Manual installation may be required."
else
    JLESS_ASSET_NAME="jless-${LATEST_JLESS_TAG}-x86_64-unknown-linux-gnu.zip"
    LATEST_JLESS_URL=$(curl -s https://api.github.com/repos/PaulJuliusMartinez/jless/releases/tags/${LATEST_JLESS_TAG} | jq -r --arg ASSET_NAME "$JLESS_ASSET_NAME" '.assets[] | select(.name == $ASSET_NAME) | .browser_download_url')

    if [ -z "$LATEST_JLESS_URL" ] || [ "$LATEST_JLESS_URL" == "null" ]; then
        echo "Failed to find download URL for ${JLESS_ASSET_NAME}."
    else
        echo "Downloading jless from $LATEST_JLESS_URL"
        if wget "$LATEST_JLESS_URL" -O jless.zip; then
            if command_exists unzip; then
                unzip jless.zip -d jless_unzipped
                mv jless_unzipped/jless ~/bin/jless
                rm -rf jless_unzipped jless.zip
                echo "jless installed successfully."
            else
                echo "unzip command not found. Please install unzip."
                rm jless.zip
            fi
        else
            echo "Failed to download jless."
        fi
    fi
fi

# k9s
# Instructions: https://k9scli.io/topics/install/
echo "Installing k9s..."
wget https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz -O k9s.tar.gz
tar -xzf k9s.tar.gz
mv k9s ~/bin/k9s

# lazygit
# Instructions: https://github.com/jesseduffield/lazygit?tab=readme-ov-file#installation
echo "Installing lazygit..."
LATEST_LAZYGIT_TAG=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name)
if [ -z "$LATEST_LAZYGIT_TAG" ] || [ "$LATEST_LAZYGIT_TAG" == "null" ]; then
    echo "Failed to fetch latest lazygit tag. Manual installation may be required."
else
    # Extract version number from tag (e.g., v0.41.0 -> 0.41.0)
    LAZYGIT_VERSION=$(echo $LATEST_LAZYGIT_TAG | sed 's/v//')
    LATEST_LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/${LATEST_LAZYGIT_TAG}/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz"
    echo "Downloading lazygit from $LATEST_LAZYGIT_URL"
    if wget "$LATEST_LAZYGIT_URL" -O lazygit.tar.gz; then
        tar -xzf lazygit.tar.gz
        mv lazygit ~/bin/lazygit
        rm lazygit.tar.gz
        echo "lazygit installed successfully."
    else
        echo "Failed to download lazygit."
    fi
fi

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
echo "Installing Hack Nerd Font..."
if [ ! -d ~/nerd-fonts ]; then
    git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ~/nerd-fonts
fi
cd ~/nerd-fonts
./install.sh Hack
fc-cache -f -v
cd ~

# gcloud-cli
# Instructions: https://cloud.google.com/sdk/docs/install
echo "Manual installation needed for gcloud-cli. Please see: https://cloud.google.com/sdk/docs/install"

# VSCode Extensions - Install via VSCode UI or code command
echo "Install VSCode extensions: github.copilot-chat, ms-azuretools.vscode-containers using the VSCode UI or the 'code --install-extension' command."

echo "Linux installation script finished."
