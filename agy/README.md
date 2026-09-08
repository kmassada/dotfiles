# Declarative AI Agent Setup Engine

Provisioning engine and declarative configuration system for AI coding agents,
including Google Antigravity (AGY), Gemini CLI, and Claude Code.

This directory orchestrates universal agent skills, conditional rules, Model
Context Protocol (MCP) servers, model provider configurations, and
authentication credentials using a declarative, config-driven architecture.

---

## Declarative Architecture (`targets.json`)

All source locations and agent-specific discovery requirements are declared in
[`targets.json`](file:///Users/kmassada/src/dotfiles/agy/targets.json):

```json
{
  "sources": {
    "skills_dir": "~/.agents/skills",
    "rules_dir": "~/.agents/rules",
    "mcp_file": "~/.agents/mcp/mcp_config.json"
  },
  "targets": {
    "antigravity": {
      "name": "Google Antigravity & Gemini CLI",
      "mcp": {
        "target_file": "~/.gemini/config/mcp_config.json",
        "symlink_to": "~/.gemini/antigravity-cli/mcp_config.json"
      },
      "json_entries": [
        {
          "target_file": "~/.gemini/config/skills.json",
          "source": "skills_dir"
        },
        {
          "target_file": "~/.gemini/config/rules.json",
          "source": "rules_dir"
        }
      ],
      "settings": {
        "target_file": "~/.gemini/antigravity-cli/settings.json",
        "key": "modelProvider",
        "value": "gemini"
      }
    },
    "claude": {
      "name": "Claude Code",
      "skills_dir": "~/.claude/skills",
      "mcp": {
        "target_file": "~/.claude.json"
      }
    }
  }
}
```

### Generic Primitives

The Python engine
[`config.py`](file:///Users/kmassada/src/dotfiles/agy/config.py)
implements generic, stateless primitives:

1. **`check_mcp` / `apply_mcp`**: Merges `mcpServers` objects into target JSON
   files without clobbering unrelated top-level keys.
2. **`check_skill_symlinks` / `apply_skill_symlinks`**: Scans upstream skill
   packages (directories with `SKILL.md`) and symlinks them into target tool
   directories without overwriting non-symlink user directories.
3. **`check_json_entry` / `apply_json_entry`**: Idempotently registers paths
   into JSON registry files (`skills.json`, `rules.json`).
4. **`check_json_key` / `apply_json_key`**: Sets or verifies top-level key-value
   pairs (`settings.json`).
5. **`check_symlink` / `apply_symlink`**: Ensures file or directory symlinks.

---

## File Structure

* **`targets.json`**: Declarative mapping of upstream sources and downstream
  agent targets.
* **`config.py`**: Lean, zero-dependency Python engine. Complies with PEP 723
  and uses abstract typing from `collections.abc`.
* **`test_config.py`**: Hermetic unit test suite verifying each primitive and
  the end-to-end engine against an isolated temporary directory.
* **`setup.sh`**: Top-level shell script wrapping directory creation, upstream
  git synchronization, agent configuration, and environment credentials.

---

## Usage

### Audit Configuration

Run the shell script without flags to check overall system health:

```bash
./agy/setup.sh
```

Or run the Python engine directly to audit all targets or an individual agent:

```bash
python3 agy/config.py audit
python3 agy/config.py audit --target claude
python3 agy/config.py audit --target antigravity
```

Structured JSON output is also supported:

```bash
python3 agy/config.py audit --format json
```

### Apply Configuration

Apply missing directories, sync upstream skills, and configure discovery:

```bash
./agy/setup.sh --apply
```

Or apply target configurations individually:

```bash
python3 agy/config.py apply --target claude
```

### Configure Credentials

Set your Gemini API key in `~/.local/gemini_auth.zsh` and export to macOS
`launchctl`:

```bash
./agy/setup.sh --apply --key "AIzaSy..."
```

For Slack MCP credentials, use the dedicated Slack bootstrapper:

```bash
./scripts/setup-slack.sh --apply
```

---

## Adding New Agents (e.g. Cursor or Windsurf)

Because the architecture is config-driven, supporting a new agent does **not**
require editing Python code or creating new files. Simply add a new target block
to `targets.json`:

```json
"cursor": {
  "name": "Cursor",
  "mcp": {
    "target_file": "~/.cursor/mcp.json"
  }
}
```

Running `python3 agy/config.py audit` or `apply` will automatically discover and
configure the new target.

---

## Development & Verification

All Python code adheres to strict quality and typing standards:

* **Unit Testing**: Run hermetic unit tests with standard library `unittest`:

  ```bash
  python3 -m unittest discover -s agy
  ```

* **Static Type Checking**: Verify static types with Pyright:

  ```bash
  uvx pyright agy/
  ```

* **Formatting & Linting**: Check and format with Ruff:

  ```bash
  uvx ruff check agy/
  uvx ruff format --check agy/
  ```
