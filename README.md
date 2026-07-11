# 📁 Dotfiles

This repository contains my personal terminal and shell configuration. It is set
up for speed and minimalism, utilizing `fzf`, `ripgrep`, and Vim keybindings.

## 🛠️ Core Tools

Here are the core applications that drive this setup:

*   **`bat`**: A highly improved `cat` clone with syntax highlighting and Git
    integration.
*   **`eza`**: A modern, colorful, and icon-rich replacement for the standard
    `ls` command.
*   **`fzf`**: A blazing fast command-line fuzzy finder used for searching
    history, files, and more.
*   **`gh`**: GitHub CLI.
*   **`git-delta`**: A syntax-highlighting pager for git, diff, and grep output.
*   **`jless`**: A command-line JSON viewer.
*   **`jq`**: Lightweight and flexible command-line JSON processor.
*   **`k9s`**: A terminal-based UI to seamlessly monitor and interact with
    Kubernetes clusters.
*   **`kubectl`**: Kubernetes command-line tool.
*   **`kubectx`**: Tool to switch between contexts (clusters) on kubectl faster.
*   **`lazygit`**: A simple terminal UI for git commands.
*   **`neovim`**: A highly extensible Vim-based text editor (aliased to `vim`
    and used as the default `$EDITOR`).
*   **`podman`**: Daemonless container engine.
*   **`powerlevel10k`**: The engine behind the fast, informative, and stylish
    Zsh prompt.
*   **`ripgrep`**: An extremely fast search tool that completely replaces `grep`
    and powers the backend of `fzf`.
*   **`stow`**: A GNU symlink farm manager used to instantly install and manage
    these dotfiles.
*   **`tmux`**: A powerful terminal multiplexer for managing multiple panes and
    sessions (configured with a custom `Ctrl+Space` prefix).
*   **`wget`**: Utility for non-interactive download of files from the web.
*   **`yq`**: A command-line YAML, JSON, and XML processor.
*   **`zsh`**: The Z shell.

### Zsh Plugins

*   **`fzf-tab`**: Interactive completion menu for Zsh.
*   **`zsh-autocomplete`**: Real-time typeahead autocompletion for Zsh.
*   **`zsh-autosuggestions`**: Suggests commands based on history.
*   **`zsh-completions`**: Additional completion definitions for Zsh.
*   **`zsh-syntax-highlighting`**: Colorizes commands in the shell.

## 🛠️ Supported Operating Systems

This configuration supports both **macOS** and **Linux** (Debian/Ubuntu based).
The `.zshrc` file contains conditional logic to handle OS-specific paths and
package management.

## 🚀 Installation

This setup uses GNU `stow` to manage symlinks and configuration files
automatically across your home directory.

### Step 1: Clone & Prepare Local Overrides

Clone the repository and create your local machine-specific override directory
(`~/.local/init.zsh`) before stowing:

```bash
git clone https://github.com/kmassada/dotfiles.git ~/src/dotfiles
cd ~/src/dotfiles
mkdir -p ~/.local && touch ~/.local/init.zsh
```

### Step 2: Install Package Dependencies (By OS)

#### Linux (Debian/Ubuntu)

Run the automated installation scripts to install packages and Zsh plugins:

```bash
chmod +x install_linux.sh install_zsh_plugins.sh
./install_linux.sh
./install_zsh_plugins.sh
```

#### macOS

Install all required tools, casks, and taps using the Brewfile:

```bash
brew bundle install --file=~/src/dotfiles/Brewfile
```

### Step 3: Backup Existing Files & Symlink (`stow`)

Backup any pre-existing shell configuration files to a temporary folder so
`stow` can link cleanly:

```bash
mkdir -p ~/tmp_dotfiles_backup
mv ~/.zshrc ~/.zsh_aliases ~/.tmux.conf ~/.p10k.zsh ~/.rgignore ~/tmp_dotfiles_backup/ 2>/dev/null
stow --adopt -t ~ .
```

> [!NOTE] The `--adopt` flag tells `stow` to link your files while adopting any
> local customizations into the repository. After installing on Linux, restart
> your terminal or source `~/.zshrc` for all changes to take effect. If prompted
> by Powerlevel10k on first run, configure it using `p10k configure`.

## 🏗️ Architecture & Configuration

### 1. 🔍 Search and Navigation (`fzf` + `ripgrep`)

The default Zsh completion is replaced with `fzf-tab` to provide an interactive
menu.

*   `ripgrep` is configured as the default command for `fzf`.
*   A custom `_fzf_compgen_path` function ensures `** + Tab` triggers `ripgrep`
    instead of the default `find` command.
*   `eza` is used to provide colored previews for directories within `fzf`.

### 2. 🚫 Ignore Rules (`.rgignore`)

The `~/.rgignore` file defines strict rules to keep search results clean by
blocking:

*   macOS specific files (`.DS_Store`, `Library/`, etc.)
*   Node and Python caches (`node_modules/`, `__pycache__/`)
*   VS Code workspace history

### 3. 🔌 Zsh Plugins

Plugins are loaded dynamically in `.zshrc`:

1.  **`fzf-tab`**: Interactive completion menu (loaded after `compinit`).
2.  **`zsh-autosuggestions`**: Suggests commands based on history.
3.  **`zsh-syntax-highlighting`**: Colorizes commands.

### 4. ⌨️ Keybindings & Editor

*   **Vi Mode:** The shell is configured to use Vi keybindings (`bindkey -v`).
*   **Command Editing:** Press `Ctrl + X`, `Ctrl + E` (or `v` in normal mode) to
    edit the current command line in Neovim.
*   **Cursor Shape:** The cursor automatically changes between a block (command
    mode) and a beam (insert mode).

### 5. 🪟 Tmux (`.tmux.conf`)

*   **Prefix:** Changed to `Ctrl + Space`.
*   **Window/Pane Index:** Starts at 1 instead of 0.
*   **Mouse:** Enabled.
*   **Splitting:** `"` for vertical, `%` for horizontal, both opening in the
    current path.
*   **Focus & Auto-Renaming:** Automatically updates window names to match the
    focused pane's custom title across pane switches (`pane-focus-in`).

## 🎨 Theming

The setup uses the **Apprentice** color palette
(https://romainl.github.io/Apprentice/).

1.  **Terminal Colors:** Configure your terminal emulator (iTerm2, Alacritty,
    etc.) to use the Apprentice color scheme.
2.  **Prompt (Powerlevel10k):** Uses the "Pure" style. If you re-run the wizard
    (`p10k configure`), use these options to match this setup:
    *   **Prompt Style:** `Pure`
    *   **Prompt Color:** `Original`
    *   **Non-permanent Content:** `Right side`
    *   **Current Time:** `No`
    *   **Prompt Height:** `2 lines`
    *   **Prompt Spacing:** `Sparse`
    *   **Enable Transient Prompt:** `False`
    *   **Instant Prompt:** `Verbose`
3.  **Syntax Highlighting & Tmux:** Colors in `.zshrc`
    (`zsh-syntax-highlighting`) and `.tmux.conf` (status bar) are manually
    adjusted to match the Apprentice palette.

## ⚙️ Maintenance & Helpers

### Download Helper Scripts

Additional helper scripts can be downloaded into `./scripts/` by running:

```bash
chmod +x download_scripts.sh
./download_scripts.sh
```

### Keeping Homebrew Synced (macOS)

To track changes to your Homebrew installations and update your `Brewfile`:

```bash
brew bundle dump --file=~/src/dotfiles/Brewfile --force
```

To see a concise list of only the packages you explicitly requested:

```bash
brew leaves --installed-on-request
```

To force your local packages to exactly match the contents of `Brewfile`
(removing unlisted packages):

```bash
brew bundle cleanup --file=~/src/dotfiles/Brewfile --force
```

## ⚡ Profiling & Debugging Startup

If your shell startup feels slow, you can profile and debug it using the
following methods.

### 1. Function Profiling (`zprof`)

Zsh has a built-in profiler that measures the execution time of shell functions.

1.  Add the following line to the **very top** of your `~/.zshrc`:

    ```zsh
    zmodload zsh/zprof
    ```

2.  Add the following line to the **very bottom** of your `~/.zshrc`:

    ```zsh
    zprof
    ```

3.  Open a new terminal. It will print a table showing which functions took the
    most CPU time.

*(Note: `zprof` only measures shell functions. It does not measure top-level
commands or external binary executions).*

### 2. Deep Profiling (`xtrace`)

To profile top-level commands, sourcing files, and external binaries with
nanosecond timestamps:

1.  Run the following command to generate a trace log:

    ```bash
    PS4='+%D{%s.%N} %N:%i> ' zsh -x -i -c exit 2>/tmp/zsh_trace.txt
    ```

2.  Analyze `/tmp/zsh_trace.txt` by looking for large gaps between the
    timestamps on consecutive lines. The line before the gap is the command that
    caused the delay.
