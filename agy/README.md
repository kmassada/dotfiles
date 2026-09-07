# Antigravity (AGY) & Gemini Setup Engine

Provisioning engine and configuration system for Google Antigravity (AGY),
Gemini CLI, and AI agent environments.

This directory manages universal agent skills, rules, Model Context Protocol
(MCP) servers, model provider configurations, and authentication credentials
across macOS and Linux hosts.

---

## Architecture & Layers

The setup engine orchestrates seven distinct configuration layers:

1. **Directory Structure**: Verifies and provisions base paths in
   `~/.gemini/config`, `~/.agents/skills`, `~/.agents/rules`, `~/.agents/mcp`,
   and `~/.local`.
2. **Skills, Rules, and MCP Synchronization**: Syncs standalone agent packages
   from the upstream [`agent-skills`](https://github.com/kmassada/agent-skills)
   repository into `~/.agents/`.
3. **Global Skills Discovery**: Configures `~/.gemini/config/skills.json` and
   symlinks skills into Antigravity discovery paths.
4. **Global Rules Discovery**: Configures `~/.gemini/config/rules.json` and
   links conditional and system rules.
5. **Universal MCP Configuration**: Merges Model Context Protocol definitions
   into `~/.gemini/config/mcp_config.json` and links to
   `~/.gemini/antigravity-cli/mcp_config.json`.
6. **Model Provider**: Sets `modelProvider = "gemini"` in
   `~/.gemini/antigravity-cli/settings.json`.
7. **Environment & Secrets**: Safely writes credentials (`GEMINI_API_KEY`,
   `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID`) to `~/.local/*.zsh` (mode `0600`) and
   syncs them to macOS `launchctl` for GUI applications.

---

## File Structure

* **`setup.sh`**: The primary shell driver. Supports audit mode (read-only
  inspection) and apply mode (idempotent configuration).
* **`config.py`**: The underlying Python engine. Handles JSON schema
  validation, safe entry deduplication, dictionary merging, and provider
  configuration. Fully typed with `collections.abc` and compliant with PEP 723.
* **`test_config.py`**: Hermetic companion unit test suite using standard
  library `unittest` and `tempfile.TemporaryDirectory`.

---

## Usage

### Audit Configuration

Run the shell script without flags to perform a read-only health check across
all seven layers:

```bash
./agy/setup.sh
```

### Apply Configuration

Apply missing directories, sync upstream skills, and configure discovery:

```bash
./agy/setup.sh --apply
```

### Set Gemini API Key

Configure the environment and save the API key to `~/.local/gemini_auth.zsh`
while propagating to macOS `launchctl`:

```bash
./agy/setup.sh --apply --key "AIzaSy..."
```

---

## Development & Verification

All Python code in this directory follows strict quality and typing standards:

* **Unit Testing**: Run the companion test suite:

  ```bash
  python3 -m unittest discover -s agy
  ```

* **Static Type Checking**: Verify zero errors with Pyright:

  ```bash
  uvx pyright agy/
  ```

* **Linting & Formatting**: Verify compliance with PEP 8 and Ruff:

  ```bash
  uvx ruff check agy/ && uvx ruff format --check agy/
  ```

---

## Security & Credential Hygiene

* Secrets, tokens, and private keys are **never** committed to version control.
* Sensitive values are stored exclusively in `~/.local/*.zsh` with file mode
  `0600`.
* The shell automatically sources private overrides from `~/.local/` on startup
  via `.zshrc`.
