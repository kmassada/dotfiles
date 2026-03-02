# 📁 Dotfiles

This repository contains my personal terminal and shell configuration. It is set up for speed and minimalism, utilizing `fzf`, `ripgrep`, and Vim keybindings.

## 🛠️ Prerequisites

The following tools are required and can be installed via Homebrew:

```bash
brew install fzf ripgrep eza neovim tmux gh stow
```

* `fzf`: Command-line fuzzy finder.
* `ripgrep` (`rg`): Fast search tool, used as the default search engine for `fzf`.
* `eza`: A modern replacement for `ls` providing colors and icons.
* `neovim`: Text editor, set as the default `$EDITOR` and aliased to `vim`.
* `tmux`: Terminal multiplexer.
* `gh`: GitHub CLI.
* `stow`: Symlink farm manager, used to install these dotfiles.

## 🏗️ Architecture & Configuration

### 1. 🔍 Search and Navigation (`fzf` + `ripgrep`)
The default Zsh completion is replaced with `fzf-tab` to provide an interactive menu. 
* `ripgrep` is configured as the default command for `fzf`.
* A custom `_fzf_compgen_path` function ensures `** + Tab` triggers `ripgrep` instead of the default `find` command.
* `eza` is used to provide colored previews for directories within `fzf`.

### 2. 🚫 Ignore Rules (`.rgignore`)
The `~/.rgignore` file defines strict rules to keep search results clean by blocking:
* macOS specific files (`.DS_Store`, `Library/`, etc.)
* Node and Python caches (`node_modules/`, `__pycache__/`)
* VS Code workspace history

### 3. 🔌 Zsh Plugins
Plugins are installed via Homebrew and loaded in the `.zshrc`:
1. **`fzf-tab`**: Interactive completion menu (loaded after `compinit`).
2. **`zsh-autosuggestions`**: Suggests commands based on history.
3. **`zsh-syntax-highlighting`**: Colorizes commands.

### 4. ⌨️ Keybindings & Editor
* **Vi Mode:** The shell is configured to use Vi keybindings (`bindkey -v`).
* **Command Editing:** Press `Ctrl + X`, `Ctrl + E` (or `v` in normal mode) to edit the current command line in Neovim.
* **Cursor Shape:** The cursor automatically changes between a block (command mode) and a beam (insert mode).

### 5. 🪟 Tmux (`.tmux.conf`)
* **Prefix:** Changed to `Ctrl + Space`.
* **Window/Pane Index:** Starts at 1 instead of 0.
* **Mouse:** Enabled.
* **Splitting:** `"` for vertical, `%` for horizontal, both opening in the current path.

## 🎨 Theming

The setup uses the **Apprentice** color palette (https://romainl.github.io/Apprentice/).

1. **Terminal Colors:** iTerm2/Terminal emulator should be configured to use the Apprentice color scheme.
2. **Prompt (Powerlevel10k):** Uses the "Pure" style. If you ever need to re-run the configuration wizard (`p10k configure`), here are the settings to match this setup:
   *   **Prompt Style:** `Pure`
   *   **Prompt Color:** `Original`
   *   **Non-permanent Content:** `Right side`
   *   **Current Time:** `No`
   *   **Prompt Height:** `2 lines`
   *   **Prompt Spacing:** `Sparse`
   *   **Enable Transient Prompt:** `False`
   *   **Instant Prompt:** `Verbose`
3. **Syntax Highlighting & Tmux:** Colors in `.zshrc` (for `zsh-syntax-highlighting`) and `.tmux.conf` (status bar) have been manually adjusted to match the Apprentice palette.

## 📦 Installed Apps

Here are the core "power user" applications that drive this setup:

*   **`bat`**: A highly improved `cat` clone with syntax highlighting and Git integration.
*   **`eza`**: A modern, colorful, and icon-rich replacement for the standard `ls` command.
*   **`fzf`**: A blazing fast command-line fuzzy finder used for searching history, files, and more.
*   **`k9s`**: A terminal-based UI to seamlessly monitor and interact with Kubernetes clusters.
*   **`neovim`**: A highly extensible Vim-based text editor (aliased to `vim` and used as the default `$EDITOR`).
*   **`powerlevel10k`**: The engine behind the fast, informative, and stylish Zsh prompt.
*   **`ripgrep`**: An extremely fast search tool that completely replaces `grep` and powers the backend of `fzf`.
*   **`stow`**: A GNU symlink farm manager used to instantly install and manage these dotfiles.
*   **`tmux`**: A powerful terminal multiplexer for managing multiple panes and sessions (configured with a custom `Ctrl+Space` prefix).

*(Note: Other utility tools like `gh`, `jq`, `kubectx`, and `podman` are also frequently used alongside this stack).*

### 🔄 Keeping Homebrew Synced

To track changes to your Homebrew installations and commit them to version control, you can generate a **Brewfile** which captures every package, cask, and tap in your current environment:

```bash
# Generate/Update the Brewfile inside your dotfiles directory
brew bundle dump --file=~/src/dotfiles/Brewfile --force
```

#### 🌿 Viewing Your "Leaves" (Alternative)
If you just want a quick, human-readable list of only the core packages you've explicitly installed (ignoring all their background dependencies), run:

```bash
brew leaves --installed-on-request
```
This is a great way to see exactly what you've added to your system without the noise of the underlying "dependency tree."

## 🚀 Installation

This setup uses GNU `stow` to manage symlinks automatically.

```bash
# 1. Clone the repository into a dedicated folder
git clone <your-repo-url> ~/src/dotfiles
cd ~/src/dotfiles

# 2. Restore your applications from the Brewfile
brew bundle install --file=~/src/dotfiles/Brewfile

# 3. Backup existing configurations to a temporary folder
mkdir ~/tmp_dotfiles_backup
mv ~/.zshrc ~/.zsh_aliases ~/.tmux.conf ~/.p10k.zsh ~/.rgignore ~/tmp_dotfiles_backup/ 2>/dev/null

# 4. Use Stow to create the symlinks
# The --adopt flag tells stow to overwrite the repository files with any local changes 
# (useful if you already have custom configurations in your home directory).
stow --adopt -t ~ .
```

### 🧹 Cleaning Up Extraneous Apps
If you want to force your machine to *exactly* match the contents of your `Brewfile` (meaning it will uninstall anything you installed manually that isn't documented in the file), you can run:

```bash
brew bundle cleanup --file=~/src/dotfiles/Brewfile --force
```