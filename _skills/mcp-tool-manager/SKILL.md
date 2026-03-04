---
name: mcp-tool-manager
description: Dynamically manage disabledTools in project-scoped MCP profiles (_mcp_profiles/[project].json)
---

# MCP Tool Manager

This skill allows the agent to dynamically manage the enabled/disabled state of specific tools within a project's MCP profile (`_mcp_profiles/[project].json`).

## Goal
To programmatically edit the `disabledTools` array in a project's MCP profile JSON file, and then trigger `ag-switch.sh` to safely propagate those changes to the global `mcp_config.json`.

## When to use this skill
- When the user asks to "activate [Tool Name] tools"
- When the user asks to "disable [Tool Name] tools"
- When the agent realizes a specific tool from an active MCP needs to be exposed or hidden for the current project context.

## Prerequisites
The project must already have an active profile in `~/AG_master_files/_mcp_profiles/[project].json`.

## How to use this skill

### 1. Identify the Target
- Identify the active project name (e.g., from `CLAUDE.md`).
- Identify the exact tool names to be disabled or enabled.

### 2. Identify the Profile Path
The profile path is always: `~/AG_master_files/_mcp_profiles/[project].json`

### 3. Execution (Python Script)
Use the `run_command` tool to execute the following Python script inside WSL. Replace `[PROJECT_NAME]` and `[TOOL_NAMES_TO_TOGGLE]` appropriately.
*Note: To enable a tool, you remove it from the `disabledTools` list. To disable a tool, you add it to the `disabledTools` list.*

```python
# Save this block as a temporary script or run it inline via python3 -c
import json
import os
import sys

project_name = "PROJECT_NAME_HERE" # e.g., "alfred"
profile_path = os.path.expanduser(f"~/AG_master_files/_mcp_profiles/{project_name}.json")
tools_to_toggle = ["tool1", "tool2"] # List of exact tool names
action = "enable" # or "disable"

if not os.path.exists(profile_path):
    print(f"Error: Profile not found at {profile_path}")
    sys.exit(1)

with open(profile_path, 'r') as f:
    config = json.load(f)

# Ensure disabledTools array exists at the root of the profile
if "disabledTools" not in config:
    config["disabledTools"] = []

current_disabled = set(config["disabledTools"])

if action == "disable":
    current_disabled.update(tools_to_toggle)
elif action == "enable":
    current_disabled.difference_update(tools_to_toggle)

config["disabledTools"] = list(current_disabled)

with open(profile_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Successfully updated {profile_path}")
print("Now run: bash ~/AG_master_files/_scripts/ag-switch.sh and hit Refresh in the MCP panel.")
```

### 4. Trigger the Sync
After successfully modifying the JSON profile, you **MUST** run the sync script so that `ag-switch` compiles the changes into the master config:

```bash
bash ~/AG_master_files/_scripts/ag-switch.sh
```

### 5. Notify the User
Inform the user that the profile has been updated and they must click the **Refresh** button in the AG MCP panel for the tool changes to take effect in the UI.
