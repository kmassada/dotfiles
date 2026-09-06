#!/usr/bin/env python3
"""config.py - Antigravity & Skills Configuration Engine.

Handles JSON configuration management for:
  1. Universal skills discovery (~/.gemini/config/skills.json)
  2. Universal rules discovery (~/.gemini/config/rules.json)
  3. Universal MCP servers (~/.gemini/config/mcp_config.json)
  4. Antigravity CLI model provider (~/.gemini/antigravity-cli/settings.json)
"""

import argparse
import json
import os
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any


def resolve_path(path_str: str) -> Path:
    """Expands home directory and returns an absolute Path."""
    return Path(os.path.expanduser(path_str)).resolve()


def load_json(file_path: Path) -> dict[str, Any]:
    """Safely loads a JSON file, returning an empty dict if missing or invalid."""
    if not file_path.is_file():
        return {}
    try:
        with file_path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def save_json(file_path: Path, data: Mapping[str, Any]) -> None:
    """Safely writes formatted JSON, ensuring parent directories exist."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with file_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


# ------------------------------------------------------------------------------
# 1. Customization Entries (~/.gemini/config/skills.json & rules.json)
# ------------------------------------------------------------------------------


def check_entry(json_path: Path, target_dir_str: str) -> tuple[bool, str]:
    """Checks if target_dir is registered in JSON config entries (skills/rules).

    Returns (is_configured, status_message).
    """
    if not json_path.is_file():
        return False, "MISSING"

    data = load_json(json_path)
    entries = data.get("entries", [])

    target_abs = str(resolve_path(target_dir_str))
    target_norm = target_dir_str.replace(str(Path.home()), "~")

    for entry in entries:
        p = entry.get("path", "")
        if (
            p == target_norm
            or p == target_dir_str
            or str(resolve_path(p)) == target_abs
        ):
            return True, "CONFIGURED"

    return False, "NEEDS_UPDATE"


def apply_entry(json_path: Path, target_dir_str: str) -> bool:
    """Ensures target_dir is registered in JSON config entries.

    Returns True if an update was written, False if already present.
    """
    is_configured, _ = check_entry(json_path, target_dir_str)
    if is_configured:
        return False

    data = load_json(json_path)
    entries = data.setdefault("entries", [])

    target_norm = target_dir_str.replace(str(Path.home()), "~")
    entries.append({"path": target_norm})

    save_json(json_path, data)
    return True


def check_skills(skills_json_path: Path, target_dir_str: str) -> tuple[bool, str]:
    return check_entry(skills_json_path, target_dir_str)


def apply_skills(skills_json_path: Path, target_dir_str: str) -> bool:
    return apply_entry(skills_json_path, target_dir_str)


def check_rules(rules_json_path: Path, target_dir_str: str) -> tuple[bool, str]:
    return check_entry(rules_json_path, target_dir_str)


def apply_rules(rules_json_path: Path, target_dir_str: str) -> bool:
    return apply_entry(rules_json_path, target_dir_str)


# ------------------------------------------------------------------------------
# 2. Universal MCP Servers (~/.gemini/config/mcp_config.json)
# ------------------------------------------------------------------------------


def check_mcp(mcp_json_path: Path, source_mcp_path: Path) -> tuple[bool, str]:
    """Checks if MCP servers from source_mcp_path match target mcp_json_path.

    Returns (is_configured, status_message).
    """
    if not source_mcp_path.is_file():
        return True, "NO_SOURCE"

    source_data = load_json(source_mcp_path)
    source_servers = source_data.get("mcpServers", {})
    if not source_servers:
        return True, "EMPTY_SOURCE"

    if not mcp_json_path.is_file():
        return False, "MISSING"

    target_data = load_json(mcp_json_path)
    target_servers = target_data.get("mcpServers", {})

    for name, s_cfg in source_servers.items():
        if name not in target_servers:
            return False, "NEEDS_UPDATE"
        if target_servers[name] != s_cfg:
            return False, "NEEDS_UPDATE"

    return True, "CONFIGURED"


def apply_mcp(mcp_json_path: Path, source_mcp_path: Path) -> bool:
    """Merges MCP servers from source_mcp_path into target mcp_json_path.

    Preserves existing unmanaged servers.
    Returns True if an update was written, False if already up to date.
    """
    if not source_mcp_path.is_file():
        return False

    source_data = load_json(source_mcp_path)
    source_servers = source_data.get("mcpServers", {})
    if not source_servers:
        return False

    target_data = load_json(mcp_json_path)
    target_servers = target_data.setdefault("mcpServers", {})

    changed = False
    for name, s_cfg in source_servers.items():
        if target_servers.get(name) != s_cfg:
            target_servers[name] = s_cfg
            changed = True

    if changed:
        save_json(mcp_json_path, target_data)
        return True

    return False


# ------------------------------------------------------------------------------
# 3. Antigravity Settings (~/.gemini/antigravity-cli/settings.json)
# ------------------------------------------------------------------------------


def get_provider(agy_settings_path: Path) -> str:
    """Returns current modelProvider string from antigravity settings."""
    if not agy_settings_path.is_file():
        return ""
    data = load_json(agy_settings_path)
    return str(data.get("modelProvider", ""))


def check_provider(agy_settings_path: Path, expected_provider: str) -> tuple[bool, str]:
    """Checks if modelProvider matches expected value in antigravity settings.

    Returns (is_configured, current_value_or_status).
    """
    if not agy_settings_path.is_file():
        return False, "MISSING"

    current = get_provider(agy_settings_path)
    if current == expected_provider:
        return True, "CONFIGURED"

    return False, f"CURRENT_{current}" if current else "NOT_SET"


def apply_provider(agy_settings_path: Path, provider: str) -> bool:
    """Sets modelProvider in antigravity settings, preserving other fields.

    Returns True if updated, False if already set.
    """
    is_configured, _ = check_provider(agy_settings_path, provider)
    if is_configured:
        return False

    data = load_json(agy_settings_path)
    data["modelProvider"] = provider
    save_json(agy_settings_path, data)
    return True


# ------------------------------------------------------------------------------
# CLI Interface
# ------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Antigravity JSON Configuration Engine",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    # Global flags
    parser.add_argument(
        "--skills-dir",
        default="~/.agents/skills",
        help="Universal skills directory",
    )
    parser.add_argument(
        "--rules-dir",
        default="~/.agents/rules",
        help="Universal rules directory",
    )
    parser.add_argument(
        "--mcp-source",
        default="~/.agents/mcp/mcp_config.json",
        help="Path to source mcp_config.json",
    )
    parser.add_argument(
        "--mcp-json",
        default="~/.gemini/config/mcp_config.json",
        help="Path to global mcp_config.json",
    )
    parser.add_argument(
        "--model-provider",
        default="gemini",
        help="Target model provider name",
    )
    parser.add_argument(
        "--skills-json",
        default="~/.gemini/config/skills.json",
        help="Path to global skills.json",
    )
    parser.add_argument(
        "--rules-json",
        default="~/.gemini/config/rules.json",
        help="Path to global rules.json",
    )
    parser.add_argument(
        "--agy-settings",
        default="~/.gemini/antigravity-cli/settings.json",
        help="Path to antigravity settings.json",
    )
    parser.add_argument(
        "--format",
        choices=["human", "json"],
        default="human",
        help="Output format for audit/apply",
    )

    # Command options (can be passed as command or flag)
    parser.add_argument(
        "--audit", action="store_true", help="Audit full configuration status"
    )
    parser.add_argument(
        "--apply", action="store_true", help="Apply full configuration changes"
    )

    parser.add_argument(
        "action",
        nargs="?",
        choices=[
            "audit",
            "apply",
            "check-skills",
            "apply-skills",
            "check-rules",
            "apply-rules",
            "check-mcp",
            "apply-mcp",
            "check-provider",
            "apply-provider",
            "get-provider",
        ],
        help="Specific action to perform",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    skills_json = resolve_path(args.skills_json)
    rules_json = resolve_path(args.rules_json)
    mcp_json = resolve_path(args.mcp_json)
    agy_settings = resolve_path(args.agy_settings)

    mcp_source = resolve_path(args.mcp_source)
    if not mcp_source.is_file():
        fallback_source = resolve_path("~/src/agent-skills/mcp/mcp_config.json")
        if fallback_source.is_file():
            mcp_source = fallback_source

    action = args.action
    if not action:
        if args.apply:
            action = "apply"
        else:
            action = "audit"

    if action == "check-skills":
        ok, status = check_skills(skills_json, args.skills_dir)
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-skills":
        updated = apply_skills(skills_json, args.skills_dir)
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-rules":
        ok, status = check_rules(rules_json, args.rules_dir)
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-rules":
        updated = apply_rules(rules_json, args.rules_dir)
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-mcp":
        ok, status = check_mcp(mcp_json, mcp_source)
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "apply-mcp":
        updated = apply_mcp(mcp_json, mcp_source)
        print("UPDATED" if updated else "ALREADY_CONFIGURED")
        sys.exit(0)

    elif action == "check-provider":
        ok, status = check_provider(agy_settings, args.model_provider)
        print(status)
        sys.exit(0 if ok else 1)

    elif action == "get-provider":
        print(get_provider(agy_settings))
        sys.exit(0)

    elif action == "apply-provider":
        updated = apply_provider(agy_settings, args.model_provider)
        print("UPDATED" if updated else "ALREADY_SET")
        sys.exit(0)

    elif action == "apply":
        updated_skills = apply_skills(skills_json, args.skills_dir)
        updated_rules = apply_rules(rules_json, args.rules_dir)
        updated_mcp = apply_mcp(mcp_json, mcp_source)
        updated_agy = apply_provider(agy_settings, args.model_provider)

        if args.format == "json":
            print(
                json.dumps(
                    {
                        "status": "applied",
                        "skills_json_updated": updated_skills,
                        "rules_json_updated": updated_rules,
                        "mcp_config_updated": updated_mcp,
                        "agy_settings_updated": updated_agy,
                    }
                )
            )
        else:
            skills_msg = "Updated" if updated_skills else "Already configured"
            rules_msg = "Updated" if updated_rules else "Already configured"
            mcp_msg = "Updated" if updated_mcp else "Already configured"
            agy_msg = "Updated" if updated_agy else "Already configured"
            print(f"skills_json: {skills_msg}")
            print(f"rules_json: {rules_msg}")
            print(f"mcp_config: {mcp_msg}")
            print(f"antigravity_settings: {agy_msg}")
        sys.exit(0)

    elif action == "audit":
        skills_ok, skills_status = check_skills(skills_json, args.skills_dir)
        rules_ok, rules_status = check_rules(rules_json, args.rules_dir)
        mcp_ok, mcp_status = check_mcp(mcp_json, mcp_source)
        agy_ok, agy_status = check_provider(agy_settings, args.model_provider)

        if args.format == "json":
            print(
                json.dumps(
                    {
                        "skills_json": {
                            "ok": skills_ok,
                            "status": skills_status,
                        },
                        "rules_json": {"ok": rules_ok, "status": rules_status},
                        "mcp_config": {"ok": mcp_ok, "status": mcp_status},
                        "antigravity_settings": {
                            "ok": agy_ok,
                            "status": agy_status,
                        },
                    }
                )
            )
        else:
            print(f"skills_json_status: {skills_status}")
            print(f"rules_json_status: {rules_status}")
            print(f"mcp_config_status: {mcp_status}")
            print(f"antigravity_settings_status: {agy_status}")

        all_ok = skills_ok and rules_ok and mcp_ok and agy_ok
        sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
