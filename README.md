# 📁 Dotfiles

This repository contains my personal terminal and shell configuration. It is set
up for speed and minimalism, utilizing `fzf`, `ripgrep`, and Vim keybindings.

## 🛠️ Core Tools

Here are the core applications that drive this setup:

* **`bat`**: A highly improved `cat` clone with syntax highlighting and Git
    integration.
* **`eza`**: A modern, colorful, and icon-rich replacement for the standard
    `ls` command.
* **`fzf`**: A blazing fast command-line fuzzy finder used for searching
    history, files, and more.
* **`gh`**: GitHub CLI.
* **`git-delta`**: A syntax-highlighting pager for git, diff, and grep output.
* **`jless`**: A command-line JSON viewer.
* **`jq`**: Lightweight and flexible command-line JSON processor.
* **`k9s`**: A terminal-based UI to seamlessly monitor and interact with
    Kubernetes clusters.
* **`kubectl`**: Kubernetes command-line tool.
* **`kubectx`**: Tool to switch between contexts (clusters) on kubectl faster.
* **`lazygit`**: A simple terminal UI for git commands.
* **`neovim`**: A highly extensible Vim-based text editor (aliased to `vim`
    and used as the default `$EDITOR`).
* **`podman`**: Daemonless container engine.
* **`powerlevel10k`**: The engine behind the fast, informative, and stylish
    Zsh prompt.
* **`ripgrep`**: An extremely fast search tool that completely replaces `grep`
    and powers the backend of `fzf`.
* **`stow`**: A GNU symlink farm manager used to instantly install and manage
    these dotfiles.
* **`tmux`**: A powerful terminal multiplexer for managing multiple panes and
    sessions (configured with a custom `Ctrl+Space` prefix).
* **`wget`**: Utility for non-interactive download of files from the web.
* **`yq`**: A command-line YAML, JSON, and XML processor.
* **`zsh`**: The Z shell.

### Zsh Plugins

* **`fzf-tab`**: Interactive completion menu for Zsh.
* **`zsh-autocomplete`**: Real-time typeahead autocompletion for Zsh.
* **`zsh-autosuggestions`**: Suggests commands based on history.
* **`zsh-completions`**: Additional completion definitions for Zsh.
* **`zsh-syntax-highlighting`**: Colorizes commands in the shell.

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

#### macOS (Automated Bootstrap)

Run the automated bootstrap script to install Xcode CLI tools, Homebrew, GNU
Stow, Brewfile packages (CLI, Casks, Mac App Store via `mas`), dotfiles, and
GitHub SSH key:

```bash
chmod +x bootstrap_mac.sh
./bootstrap_mac.sh
```

**Configurable Options:**

```bash
./bootstrap_mac.sh                                # Full install (auto-detects)
./bootstrap_mac.sh --role server --name mac-mini  # Mac Mini server setup
./bootstrap_mac.sh --cli-only                     # CLI & dotfiles only
./bootstrap_mac.sh --no-mas                       # Skip Mac App Store
./bootstrap_mac.sh --no-casks                     # Skip GUI casks
./bootstrap_mac.sh --no-settings                  # Skip macOS system settings
./bootstrap_mac.sh --no-machine                   # Skip machine identity setup
./bootstrap_mac.sh --no-agents                    # Skip AI agents setup
./bootstrap_mac.sh --no-ssh                       # Skip SSH key setup
./bootstrap_mac.sh --no-sshd                      # Skip SSH server setup
```

Or manually install via Homebrew bundle:

```bash
brew bundle install --file=~/src/dotfiles/Brewfile
```

### Step 3: Backup Existing Files & Symlink (`stow`)

Backup any pre-existing shell configuration files to a temporary folder so
`stow` can link cleanly:

```bash
mkdir -p ~/tmp_dotfiles_backup
mv ~/.zshrc ~/.zsh_aliases ~/.tmux.conf ~/.p10k.zsh ~/.rgignore \
  ~/tmp_dotfiles_backup/ 2>/dev/null
stow --adopt -t ~ .
```

> [!NOTE] The `--adopt` flag tells `stow` to link your files while adopting any
> local customizations into the repository. After installing on Linux, restart
> your terminal or source `~/.zshrc` for all changes to take effect. If prompted
> by Powerlevel10k on first run, configure it using `p10k configure`.

### Step 4: Apply macOS Preferences & Manual Polish

Apply codified Dock and Finder preferences (no magnification, bottom position,
scale effect, hidden files, extensions):

```bash
./scripts/macos-settings.sh --apply
```

For Apple-protected settings (Finder Sidebar sections/ordering, Apple ID, Touch
ID `sudo`), complete the 3-minute checklist in
**[`SETUP_MANUAL.md`](SETUP_MANUAL.md)**.

## 🏗️ Architecture & Configuration

### 1. 🔍 Search and Navigation (`fzf` + `ripgrep`)

The default Zsh completion is replaced with `fzf-tab` to provide an interactive
menu.

* `ripgrep` is configured as the default command for `fzf`.
* A custom `_fzf_compgen_path` function ensures `** + Tab` triggers `ripgrep`
    instead of the default `find` command.
* `eza` is used to provide colored previews for directories within `fzf`.

### 2. 🚫 Ignore Rules (`.rgignore`)

The `~/.rgignore` file defines strict rules to keep search results clean by
blocking:

* macOS specific files (`.DS_Store`, `Library/`, etc.)
* Node and Python caches (`node_modules/`, `__pycache__/`)
* VS Code workspace history

### 3. 🔌 Zsh Plugins

Plugins are loaded dynamically in `.zshrc`:

1. **`fzf-tab`**: Interactive completion menu (loaded after `compinit`).
2. **`zsh-autosuggestions`**: Suggests commands based on history.
3. **`zsh-syntax-highlighting`**: Colorizes commands.

### 4. ⌨️ Keybindings & Editor

* **Vi Mode:** The shell is configured to use Vi keybindings (`bindkey -v`).
* **Command Editing:** Press `Ctrl + X`, `Ctrl + E` (or `v` in normal mode) to
    edit the current command line in Neovim.
* **Cursor Shape:** The cursor automatically changes between a block (command
    mode) and a beam (insert mode).

### 5. 🪟 Tmux (`.tmux.conf`)

* **Prefix:** Changed to `Ctrl + Space`.
* **Window/Pane Index:** Starts at 1 instead of 0.
* **Mouse:** Enabled.
* **Splitting:** `"` for vertical, `%` for horizontal, both opening in the
    current path.
* **Focus & Auto-Renaming:** Automatically updates window names to match the
    focused pane's custom title across pane switches (`pane-focus-in`).

## 🎨 Theming

The setup uses the **Apprentice** color palette
(<https://romainl.github.io/Apprentice/>).

1. **Terminal Colors:** Configure your terminal emulator (iTerm2, Alacritty,
    etc.) to use the Apprentice color scheme.
2. **Prompt (Powerlevel10k):** Uses the "Pure" style. If you re-run the wizard
    (`p10k configure`), use these options to match this setup:
    * **Prompt Style:** `Pure`
    * **Prompt Color:** `Original`
    * **Non-permanent Content:** `Right side`
    * **Current Time:** `No`
    * **Prompt Height:** `2 lines`
    * **Prompt Spacing:** `Sparse`
    * **Enable Transient Prompt:** `False`
    * **Instant Prompt:** `Verbose`
3. **Syntax Highlighting & Tmux:** Colors in `.zshrc`
    (`zsh-syntax-highlighting`) and `.tmux.conf` (status bar) are manually
    adjusted to match the Apprentice palette.

## 🖥️ Machine Identity & Role Provisioning

Each machine can have its own local identity, custom prompt icon, color, and
system role without generating Git repository conflicts.

### Machine Config (`~/.config/dotfiles/machine.env`)

Create or customize `~/.config/dotfiles/machine.env` on any host (a template is
available at `.config/dotfiles/machine.env.example`):

```bash
# ~/.config/dotfiles/machine.env

# 1. Machine Identity & Visuals
MACHINE_NAME="macbook-air"        # Machine alias (e.g. "mac-mini", "work-mac")
MACHINE_ICON="laptop"             # Named alias or literal character/glyph
MACHINE_ICON_COLOR="yellow"       # Foreground color for the icon
MACHINE_ROLE="client"             # "client" (laptop) or "server" (always-on)
```

### Prompt Icon Layout

The prompt displays two distinct tiers of indicators:

* **Line 1 Left (OS Indicator):** Preserves the operating system glyph (`` on
    macOS, `` on Linux).
* **Line 1 Right (Machine Icon):** Injects your custom colored icon directly
    after the hostname (`user@host <icon>`).
* **Line 2 (Prompt Character):** Retains a clean, uncluttered `❯` prompt symbol:

```text
 ~/src/dotfiles main ⇡                kmassada@Kenneths-MacBook-Air 󰌢 11:14 AM
❯ 
```

### Available Icon Names & Mappings

You can specify either predefined icon names or any raw Nerd Font glyph:

| Name | Glyph | Description |
| --- | --- | --- |
| `laptop` / `macbook` / `notebook` | `󰌢` | Portable laptop |
| `desktop` / `mac-mini` / `imac` | `` | Desktop workstation |
| `server` / `station` / `box` | `󰒋` | Always-on station / server |
| `work` / `office` | `󱥒` | Corporate / work machine |
| `home` | `󰋜` | Home machine |
| `apple` / `mac` | `` | Apple logo |
| `linux` / `tux` | `` | Linux penguin |
| `terminal` / `cli` | `` | Terminal prompt |
| `robot` / `agent` | `󰚩` | AI agent station |

### Color Options (`MACHINE_ICON_COLOR`)

* **Standard Colors:** `white`, `yellow`, `cyan`, `green`, `magenta`, `blue`,
    `red`.
* **Hex Codes:** `#88C0D0`, `#EBCB8B`, `#A3BE8C`, `#B48EAD`, `#5E81AC`.

### Hardware Roles (`client` vs `server`)

Run the unified setup helper to audit or configure roles:

```bash
# Interactive setup wizard
~/src/dotfiles/scripts/setup-machine.sh

# Audit current configuration & hardware policies
~/src/dotfiles/scripts/setup-machine.sh --status

# Non-interactive provisioning for Mac Mini server
~/src/dotfiles/scripts/setup-machine.sh --apply --role server \
  --name mac-mini --icon desktop --icon-color cyan
```

* **`client` (Laptops):** Configures standard energy-saving policies.
* **`server` (Mac Mini / Linux):**
  * **Power Management (`pmset`):** Disables system sleep (`sleep 0`),
        enables Wake-on-LAN (`womp 1`), and enables auto-restart after power
        loss (`autorestart 1`).
  * **Display Sleep:** Turns displays off after 10 minutes while CPU and
        network remain permanently active.
  * **Remote Login (SSH):** Ensures `sshd` is running on port 22 and prints
        local connection strings.

### Secrets Management with Bitwarden Secrets Manager (`bws`)

Bitwarden Secrets Manager (`bws`) provides headless, non-interactive secret
injection for scripts, agents, and MCP servers without prompting for master
passwords or personal vault logins.

#### One-Time Setup Workflow

* **Step 1 (Open Console):** Open the
  [Bitwarden Secrets Manager Console](https://vault.bitwarden.com/#/sm).
* **Step 2 (Create Project):** Create a project (e.g. `Developer-Env`) and add
  your secrets (e.g. `SLACK_BOT_TOKEN`, `GEMINI_API_KEY`).
* **Step 3 (Machine Account):** Navigate to **Machine Accounts**, create an
  account for this machine, and grant read access to the project.
* **Step 4 (Access Token):** Generate a **Machine Access Token** and save it in
  `~/.config/dotfiles/machine.env`:

```bash
# ~/.config/dotfiles/machine.env
export BWS_ACCESS_TOKEN="0.xxxxxxxx..."
```

* **Step 5 (Automation):** Once configured, dotfile scripts (like
  `setup-slack.sh`) and AI tools retrieve secrets directly without interactive
  prompts:

```bash
# Verify secret resolution
bws secret get <SECRET_UUID>

# Update bws to the latest release anytime
update_bws
```

## ⚙️ Maintenance & Helpers

### Download Helper Scripts

Additional helper scripts can be downloaded into `./scripts/` by running:

```bash
chmod +x download_scripts.sh
./download_scripts.sh
```

### Google Workspace CLI & Cloud Bootstrap (`gws`)

Audit or provision Google Workspace GCP projects, enable APIs, and configure
OAuth credentials and `pass` password store:

```bash
# Audit current gws, GCP project, and authentication state
~/src/dotfiles/scripts/setup-gws.sh

# Interactive GCP project creation, API enablement, and OAuth credential setup
~/src/dotfiles/scripts/setup-gws.sh --apply
```

#### OAuth Consent & Unverified App Notes

When authenticating via `gws auth login` with an external Google Cloud project:

* **Access Blocked (Verification Required)**: If Google blocks login with
  `Access blocked: gws has not completed the Google verification process`,
  open [Google Cloud Console OAuth Consent][gcp-oauth-consent], scroll to
  **Test users**, click **+ ADD USERS**, and add your email address.
* **Google hasn't verified this app**: In the browser consent screen, click
  **Advanced** (bottom left), then click **Go to gws CLI (unsafe)**, and
  click **Continue / Allow**.

[gcp-oauth-consent]: https://console.cloud.google.com/apis/credentials/consent

### Slack Workspace & Bot Bootstrap

Audit or provision Slack bot tokens, workspace identities, and `pass` sync:

```bash
# Audit Slack workspace token status
~/src/dotfiles/scripts/setup-slack.sh

# Interactive Slack bot token setup and validation
~/src/dotfiles/scripts/setup-slack.sh --apply
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

1. Add the following line to the **very top** of your `~/.zshrc`:

    ```zsh
    zmodload zsh/zprof
    ```

2. Add the following line to the **very bottom** of your `~/.zshrc`:

    ```zsh
    zprof
    ```

3. Open a new terminal. It will print a table showing which functions took the
    most CPU time.

*(Note: `zprof` only measures shell functions. It does not measure top-level
commands or external binary executions).*

### 2. Deep Profiling (`xtrace`)

To profile top-level commands, sourcing files, and external binaries with
nanosecond timestamps:

1. Run the following command to generate a trace log:

    ```bash
    PS4='+%D{%s.%N} %N:%i> ' zsh -x -i -c exit 2>/tmp/zsh_trace.txt
    ```

2. Analyze `/tmp/zsh_trace.txt` by looking for large gaps between the
    timestamps on consecutive lines. The line before the gap is the command that
    caused the delay.
