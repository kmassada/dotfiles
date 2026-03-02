# 🚀 My Ultimate Zsh Terminal Setup

This repository contains my personal terminal configuration. It is heavily optimized for speed, visual minimalism, and noise reduction using a custom `fzf` + `ripgrep` engine.

## 🛠 The Philosophy

* **Visuals:** Minimalist. No heavy background blocks. Using Powerlevel10k's "Pure" style  via iTerm2.
* **Search Engine:** Replaced the Mac's slow default `find` command with `ripgrep` to power all fuzzy finding.
* **Noise Reduction:** Strict ignore rules to banish macOS Library caches, VS Code history, and massive dependency folders from search results.

## 📦 Prerequisites (The Stack)

To recreate this setup on a new machine, install these via Homebrew:

```bash
brew install fzf ripgrep eza neovim

```

* `fzf`: The interactive fuzzy finder menu.
* `ripgrep` (`rg`): The blisteringly fast search engine that powers `fzf`.
* `eza`: A modern replacement for `ls` that provides colors and icons for the `fzf-tab` preview window.
* `neovim`: Aliased to `vi` in the `.zshrc` to provide out-of-the-box syntax highlighting without heavy configuration.

## 🧩 The Plugin Ecosystem

Plugins are installed via Homebrew and MUST be loaded in a strict order in the `.zshrc`:

1. **`fzf-tab`**: Replaces the standard Zsh autocomplete menu with an interactive, searchable fzf pane. (Requires `compinit` to run *before* it).
2. **`zsh-autosuggestions`**: Provides "ghost text" based on command history. Accept with the Right Arrow key.
3. **`zsh-syntax-highlighting`**: Colorizes commands as they are typed. (MUST be the absolute last plugin loaded, or it will break).

## 🧠 The "Gotchas" & Custom Architecture

### 1. The Nuclear `fzf` + `ripgrep` Integration

By default, pressing `** + Tab` in Zsh uses the system's slow `find` command and completely ignores `.rgignore` rules. To fix this "silent fallback," the `.zshrc` contains a custom override (`_fzf_compgen_path`) that physically hardwires the `**` trigger to use `ripgrep`.

### 2. Banish the Junk (`.rgignore`)

The `~/.rgignore` file is the secret weapon of this setup. `ripgrep` reads this file on every search. It is configured to explicitly block:

* `Library/` (Instantly kills thousands of VS Code workspace history files and Apple caches from clogging the search menu).
* `.antigravity/` extensions.
* `.DS_Store` and other Apple clutter.

### 3. The Preview Window Fix

Apple's native `ls` command is based on BSD and crashes if you pass it Linux flags like `--color=always`. To get a colored preview pane when using `cd ~/folder + Tab`, the `zstyle` configuration is set up to use either:

* Native: `ls -1hpG`
* Modern: `eza -1 --color=always` (Preferred)

### 4. The History 

Zsh history is loaded directly into RAM. The `.zshrc` caps `HISTSIZE` at 50,000. Setting this to something way larger like 5,000,000.

## 🎨 Theming

1. **Prompt:** Run `p10k configure`. Select "Pure" style, 2 lines, Sparse spacing, Original colors.
2. **Terminal:** iTerm2 > Profiles > Colors > Import Catppuccin Mocha `.itermcolors`.
3. Because P10k is set to "Original" colors, it absorbs the Catppuccin palette perfectly without fighting it.
