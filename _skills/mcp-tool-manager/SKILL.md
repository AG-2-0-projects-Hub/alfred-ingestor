---
name: mcp-tool-manager
description: Dynamically manage disabled tools globally (_mcp_profiles/global.json)
---

# MCP Tool Manager

This skill allows the agent to dynamically manage the enabled/disabled state of specific tools within the global MCP profile (`_mcp_profiles/global.json`). Tool-level disabling exists at the global level via `disabled` arrays, while project profiles only contain server names.

## Goal
To programmatically edit the `disabled` array for a specific MCP server in the `global.json` file, and then trigger `ag-switch.sh` to safely propagate those changes to the active `mcp_config.json`.

## When to use this skill
- When the user asks to "activate [Tool Name] tools"
- When the user asks to "disable [Tool Name] tools"
- When the agent realizes a specific tool from an active MCP needs to be exposed or hidden to optimize context or tool space.

## Prerequisites
The global profile must exist at `~/AG_master_files/_mcp_profiles/global.json`.

## How to use this skill

### 1. Identify the Target
- Identify the MCP server name that provides the tools.
- Identify the exact tool names to be disabled or enabled.

### 2. Identify the Profile Path
The profile path is always: `~/AG_master_files/_mcp_profiles/global.json`

### 3. Execution (Python Script)
Use the `run_command` tool to execute the following Python script inside WSL. Replace `[SERVER_NAME]` and `[TOOL_NAMES_TO_TOGGLE]` appropriately.
*Note: To enable a tool, you remove it from the `disabled` list. To disable a tool, you add it to the `disabled` list.*

```python
# Save this block as a temporary script or run it inline via python3 -c
import json
import os
import sys

server_name = "SERVER_NAME_HERE" # e.g., "github"
profile_path = os.path.expanduser("~/AG_master_files/_mcp_profiles/global.json")
tools_to_toggle = ["tool1", "tool2"] # List of exact tool names
action = "enable" # or "disable"

if not os.path.exists(profile_path):
    print(f"Error: Profile not found at {profile_path}")
    sys.exit(1)

with open(profile_path, 'r') as f:
    config = json.load(f)

if "mcpServers" not in config or server_name not in config["mcpServers"]:
    print(f"Error: Server {server_name} not found in global.json")
    sys.exit(1)

server_config = config["mcpServers"][server_name]

# Ensure disabled array exists
if "disabled" not in server_config:
    server_config["disabled"] = []

current_disabled = set(server_config["disabled"])

if action == "disable":
    current_disabled.update(tools_to_toggle)
elif action == "enable":
    current_disabled.difference_update(tools_to_toggle)

server_config["disabled"] = list(current_disabled)

with open(profile_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Successfully updated {profile_path}")
print("Now run: bash ~/AG_master_files/_scripts/ag-switch.sh and hit Refresh in the MCP panel.")
```

### 4. Trigger the Sync
After successfully modifying `global.json`, you **MUST** run the sync script so that `ag-switch` compiles the changes into the master config:

```bash
bash ~/AG_master_files/_scripts/ag-switch.sh
```

### 5. Notify the User
Inform the user that the global profile has been updated and they must click the **Refresh** button in the AG MCP panel for the tool changes to take effect in the UI.
