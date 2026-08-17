#!/bin/bash

# Installer script for Linux (Debian/Ubuntu based)


# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to download and install individual Nerd Fonts via GitHub release tarballs
install_nerd_fonts() {
    local fonts=("$@")
    if [ ${#fonts[@]} -eq 0 ]; then
        fonts=("Hack" "NerdFontsSymbolsOnly")
    fi

    local font_dir="$HOME/.local/share/fonts/NerdFonts"
    mkdir -p "$font_dir"

    local temp_font_dir
    temp_font_dir=$(mktemp -d)
    local updated=false

    echo "Checking and installing cherry-picked Nerd Fonts in ${font_dir}..."

    for font in "${fonts[@]}"; do
        local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.tar.xz"
        local archive="${temp_font_dir}/${font}.tar.xz"
        local extract_dir="${temp_font_dir}/${font}"
        mkdir -p "${extract_dir}"

        echo "Downloading ${font} from ${url}..."
        if wget -q --show-progress "$url" -O "$archive" 2>/dev/null || curl -sSL "$url" -o "$archive"; then
            if [ -f "$archive" ] && [ -s "$archive" ]; then
                tar -xf "$archive" -C "$extract_dir"
                find "$extract_dir" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec mv -f {} "$font_dir/" \;
                echo "  ✓ ${font} installed successfully."
                updated=true
            else
                echo "  ✗ Downloaded archive for ${font} is empty or invalid."
            fi
        else
            echo "  ✗ Failed to download ${font} from ${url}"
        fi
    done

    rm -rf "$temp_font_dir"

    if [ "$updated" = true ]; then
        echo "Refreshing font cache..."
        if command_exists fc-cache; then
            fc-cache -f "$font_dir"
        fi
        echo "Font cache updated."
    fi
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
echo "Checking git-delta..."
LATEST_DELTA_JSON=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest)
LATEST_DELTA_TAG=$(echo "$LATEST_DELTA_JSON" | jq -r .tag_name)
LATEST_DELTA_TAG_CMP=${LATEST_DELTA_TAG#v}

if [ -f "$HOME/bin/delta" ]; then
    LOCAL_DELTA_TAG=$("$HOME/bin/delta" --version | awk '{print $2}')
    LOCAL_DELTA_TAG=${LOCAL_DELTA_TAG#v}
else
    LOCAL_DELTA_TAG="none"
fi

if [ "$LOCAL_DELTA_TAG" != "$LATEST_DELTA_TAG_CMP" ]; then
    echo "Updating git-delta from $LOCAL_DELTA_TAG to $LATEST_DELTA_TAG_CMP..."
    LATEST_DELTA_URL=$(echo "$LATEST_DELTA_JSON" | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-musl.tar.gz$")) | .browser_download_url')
    if wget "$LATEST_DELTA_URL" -O git-delta.tar.gz; then
        tar -xzf git-delta.tar.gz
        mv "$(tar -tf git-delta.tar.gz | head -1 | cut -d/ -f1)/delta" ~/bin/delta
        echo "git-delta updated successfully."
    else
        echo "Failed to download git-delta."
    fi
else
    echo "git-delta is up to date ($LOCAL_DELTA_TAG)."
fi

# jless
# Instructions: https://github.com/PaulJuliusMartinez/jless?tab=readme-ov-file#installation
echo "Checking jless..."
LATEST_JLESS_JSON=$(curl -s https://api.github.com/repos/PaulJuliusMartinez/jless/releases/latest)
LATEST_JLESS_TAG=$(echo "$LATEST_JLESS_JSON" | jq -r .tag_name)

if [ -z "$LATEST_JLESS_TAG" ] || [ "$LATEST_JLESS_TAG" == "null" ]; then
    echo "Failed to fetch latest jless tag. Manual installation may be required."
else
    LATEST_JLESS_TAG_CMP=${LATEST_JLESS_TAG#v}

    if [ -f "$HOME/bin/jless" ]; then
        LOCAL_JLESS_TAG=$("$HOME/bin/jless" --version | awk '{print $2}')
        LOCAL_JLESS_TAG=${LOCAL_JLESS_TAG#v}
    else
        LOCAL_JLESS_TAG="none"
    fi

    if [ "$LOCAL_JLESS_TAG" != "$LATEST_JLESS_TAG_CMP" ]; then
        echo "Updating jless from $LOCAL_JLESS_TAG to $LATEST_JLESS_TAG_CMP..."
        JLESS_ASSET_NAME="jless-${LATEST_JLESS_TAG}-x86_64-unknown-linux-gnu.zip"
        LATEST_JLESS_URL=$(echo "$LATEST_JLESS_JSON" | jq -r --arg ASSET_NAME "$JLESS_ASSET_NAME" '.assets[] | select(.name == $ASSET_NAME) | .browser_download_url')

        if [ -z "$LATEST_JLESS_URL" ] || [ "$LATEST_JLESS_URL" == "null" ]; then
            echo "Failed to find download URL for ${JLESS_ASSET_NAME}."
        else
            echo "Downloading jless from $LATEST_JLESS_URL"
            if wget "$LATEST_JLESS_URL" -O jless.zip; then
                if command_exists unzip; then
                    unzip jless.zip -d jless_unzipped
                    mv jless_unzipped/jless ~/bin/jless
                    echo "jless updated successfully."
                else
                    echo "unzip command not found. Please install unzip."
                fi
            else
                echo "Failed to download jless."
            fi
        fi
    else
        echo "jless is up to date ($LOCAL_JLESS_TAG)."
    fi
fi

# k9s
# Instructions: https://k9scli.io/topics/install/
echo "Checking k9s..."
LATEST_K9S_JSON=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest)
LATEST_K9S_TAG=$(echo "$LATEST_K9S_JSON" | jq -r .tag_name)
LATEST_K9S_TAG_CMP=${LATEST_K9S_TAG#v}

if [ -f "$HOME/bin/k9s" ]; then
    LOCAL_K9S_TAG=$("$HOME/bin/k9s" version | awk '/Version:/ {print $2}')
    LOCAL_K9S_TAG=${LOCAL_K9S_TAG#v}
else
    LOCAL_K9S_TAG="none"
fi

if [ "$LOCAL_K9S_TAG" != "$LATEST_K9S_TAG_CMP" ]; then
    echo "Updating k9s from $LOCAL_K9S_TAG to $LATEST_K9S_TAG_CMP..."
    LATEST_K9S_URL="https://github.com/derailed/k9s/releases/download/${LATEST_K9S_TAG}/k9s_Linux_amd64.tar.gz"
    if wget "$LATEST_K9S_URL" -O k9s.tar.gz; then
        tar -xzf k9s.tar.gz
        mv k9s ~/bin/k9s
        echo "k9s updated successfully."
    else
        echo "Failed to download k9s."
    fi
else
    echo "k9s is up to date ($LOCAL_K9S_TAG)."
fi

# lazygit
# Instructions: https://github.com/jesseduffield/lazygit?tab=readme-ov-file#installation
echo "Checking lazygit..."
LATEST_LAZYGIT_JSON=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest)
LATEST_LAZYGIT_TAG=$(echo "$LATEST_LAZYGIT_JSON" | jq -r .tag_name)

if [ -z "$LATEST_LAZYGIT_TAG" ] || [ "$LATEST_LAZYGIT_TAG" == "null" ]; then
    echo "Failed to fetch latest lazygit tag. Manual installation may be required."
else
    LATEST_LAZYGIT_TAG_CMP=${LATEST_LAZYGIT_TAG#v}

    if [ -f "$HOME/bin/lazygit" ]; then
        LOCAL_LAZYGIT_TAG=$("$HOME/bin/lazygit" --version | awk -F', ' '{for(i=1;i<=NF;i++) if($i ~ /^version=/) print $i}' | cut -d= -f2)
        LOCAL_LAZYGIT_TAG=${LOCAL_LAZYGIT_TAG#v}
    else
        LOCAL_LAZYGIT_TAG="none"
    fi

    if [ "$LOCAL_LAZYGIT_TAG" != "$LATEST_LAZYGIT_TAG_CMP" ]; then
        echo "Updating lazygit from $LOCAL_LAZYGIT_TAG to $LATEST_LAZYGIT_TAG_CMP..."
        # Extract version number from tag (e.g., v0.41.0 -> 0.41.0)
        LAZYGIT_VERSION=$(echo $LATEST_LAZYGIT_TAG | sed 's/v//')
        LATEST_LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/${LATEST_LAZYGIT_TAG}/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz"
        echo "Downloading lazygit from $LATEST_LAZYGIT_URL"
        if wget "$LATEST_LAZYGIT_URL" -O lazygit.tar.gz; then
            tar -xzf lazygit.tar.gz
            mv lazygit ~/bin/lazygit
            echo "lazygit updated successfully."
        else
            echo "Failed to download lazygit."
        fi
    else
        echo "lazygit is up to date ($LOCAL_LAZYGIT_TAG)."
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

# Nerd Fonts (Cherry-picked minimal installation)
install_nerd_fonts "Hack" "NerdFontsSymbolsOnly"

# Powerlevel10k Theme
if [ -d "$HOME/.oh-my-zsh" ]; then
    if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        echo "Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    else
        echo "Powerlevel10k theme is already installed."
    fi
fi

# gcloud-cli (Method B - Manual Tarball)
echo "Installing/configuring gcloud-cli..."
# 1. If it exists in the old location, move it to ~/bin
if [ -d "$HOME/google-cloud-sdk" ] && [ ! -d "$HOME/bin/google-cloud-sdk" ]; then
    echo "Moving gcloud-cli from ~/google-cloud-sdk to ~/bin/google-cloud-sdk..."
    mv "$HOME/google-cloud-sdk" "$HOME/bin/"
fi

# 2. If it doesn't exist in the new location, download and install it
if [ ! -d "$HOME/bin/google-cloud-sdk" ]; then
    DOWNLOAD_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz"
    echo "Downloading from $DOWNLOAD_URL..."
    if wget "$DOWNLOAD_URL" -O google-cloud-cli.tar.gz; then
        mkdir -p "$HOME/bin"
        tar -xzf google-cloud-cli.tar.gz -C "$HOME/bin"
        rm google-cloud-cli.tar.gz
        # Run install script silently without modifying shell profiles
        "$HOME/bin/google-cloud-sdk/install.sh" --quiet --path-update false --command-completion false
        echo "gcloud-cli installed successfully to ~/bin/google-cloud-sdk"
    else
        echo "Failed to download gcloud-cli."
    fi
fi

# 3. Ensure gke-gcloud-auth-plugin is installed in the SDK
if [ -d "$HOME/bin/google-cloud-sdk" ]; then
    echo "Ensuring gke-gcloud-auth-plugin is installed..."
    "$HOME/bin/google-cloud-sdk/bin/gcloud" components install gke-gcloud-auth-plugin --quiet
fi

# VSCode Extensions - Install via VSCode UI or code command
echo "Install VSCode extensions: github.copilot-chat, ms-azuretools.vscode-containers using the VSCode UI or the 'code --install-extension' command."

echo "Linux installation script finished."
