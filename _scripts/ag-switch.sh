#!/bin/bash
# =============================================================================
# AG Switch — MCP Profile Switcher
# Resets mcp_config.json from global.json steady state, then applies project profile.
#
# Usage:
#   bash ~/AG_master_files/_scripts/ag-switch.sh               ← auto-detect project
#   bash ~/AG_master_files/_scripts/ag-switch.sh scraper        ← explicit project, base only
#   bash ~/AG_master_files/_scripts/ag-switch.sh scraper db-work ← base + task profile
#   bash ~/AG_master_files/_scripts/ag-switch.sh --list         ← show active MCPs + tool state
# =============================================================================

set -e

# --- Config ---
AG_ROOT="$HOME/AG_master_files"
PROFILES_DIR="$AG_ROOT/_mcp_profiles"
GLOBAL_PROFILE="$PROFILES_DIR/global.json"
MCP_CONFIG="/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Guards ---
if [[ ! -f "$MCP_CONFIG" ]]; then
  echo -e "${RED}Error: mcp_config.json not found at $MCP_CONFIG${NC}"
  exit 1
fi

if [[ ! -f "$GLOBAL_PROFILE" ]]; then
  echo -e "${RED}Error: global.json not found at $GLOBAL_PROFILE${NC}"
  echo -e "${YELLOW}Bootstrap it by copying mcp_config.json:${NC}"
  echo -e "  cp $MCP_CONFIG $GLOBAL_PROFILE"
  echo -e "${YELLOW}Then manually add 'disabled' arrays to each MCP entry (all tools disabled).${NC}"
  exit 1
fi

# --- --list flag ---
if [[ "$1" == "--list" ]]; then
  python3 << PYEOF
import json
with open("$MCP_CONFIG") as f:
    c = json.load(f)
servers = c.get("mcpServers", {})
print(f"Active config — {len(servers)} MCP(s):")
for name, cfg in servers.items():
    disabled = cfg.get("disabled", [])
    print(f"  • {name} — {len(disabled)} tool(s) disabled")
PYEOF
  exit 0
fi

# --- Detect project name from CLAUDE.md ---
detect_project() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      local name
      name=$(grep -m1 '^# ' "$dir/CLAUDE.md" | sed 's/^# //' | sed 's/ —.*//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      if [[ -n "$name" && "$name" != "ag-global-context" ]]; then
        echo "$name"
        return 0
      fi
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# --- Resolve project + optional task profile ---
if [[ -n "$1" ]]; then
  PROJECT_NAME="$1"
  TASK_PROFILE="$2"
else
  PROJECT_NAME=$(detect_project 2>/dev/null || echo "")
  TASK_PROFILE=""
  if [[ -z "$PROJECT_NAME" ]]; then
    if [[ "$PWD" == "$AG_ROOT" || "$PWD" == "$HOME/AG_master_files" ]]; then
      echo -e "${YELLOW}You are at AG root — ag-switch only runs inside a project folder.${NC}"
      echo -e "${YELLOW}Pass a project name explicitly: bash ag-switch.sh [project]${NC}"
    else
      echo -e "${RED}Error: could not detect project from CLAUDE.md.${NC}"
      echo -e "${YELLOW}Navigate to a project folder or pass the name explicitly.${NC}"
    fi
    exit 1
  fi
fi

PROFILE_FILE="$PROFILES_DIR/${PROJECT_NAME}.json"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo -e "${RED}Error: no profile found for '$PROJECT_NAME' at $PROFILE_FILE${NC}"
  echo -e "${YELLOW}Create one with new-project.sh or ask the mcp-tool-manager skill.${NC}"
  exit 1
fi

echo ""
echo -e "${CYAN}=======================================${NC}"
if [[ -n "$TASK_PROFILE" ]]; then
  echo -e "${CYAN}   AG Switch → ${PROJECT_NAME} [${TASK_PROFILE}]${NC}"
else
  echo -e "${CYAN}   AG Switch → ${PROJECT_NAME} [base]${NC}"
fi
echo -e "${CYAN}=======================================${NC}"
echo ""

# =============================================================================
# STEP 0 — Absorb any new MCPs from mcp_config.json into global.json
# New MCPs added via AG panel land in mcp_config.json first.
# We absorb them into global.json with an empty disabled list and warn the user
# to run mcp-tool-manager to define which tools are needed.
# =============================================================================
python3 << PYEOF
import json

mcp_config_path = "$MCP_CONFIG"
global_path = "$GLOBAL_PROFILE"

with open(mcp_config_path) as f:
    mcp_config = json.load(f)

with open(global_path) as f:
    global_cfg = json.load(f)

mcp_servers = mcp_config.get("mcpServers", {})
global_servers = global_cfg.setdefault("mcpServers", {})

absorbed = []
for name, entry in mcp_servers.items():
    if name not in global_servers:
        new_entry = dict(entry)
        # No disabled list yet — mcp-tool-manager will define it
        # Until then, all tools will be active for this MCP (temporary state)
        global_servers[name] = new_entry
        absorbed.append(name)

if absorbed:
    with open(global_path, 'w') as f:
        json.dump(global_cfg, f, indent=2)
    print(f"✓ Absorbed {len(absorbed)} new MCP(s) into global.json: {absorbed}")
    print(f"  → Run mcp-tool-manager to define disabled lists for these MCPs.")
else:
    print("✓ global.json up to date — no new MCPs detected")
PYEOF

# =============================================================================
# STEP 1 — Reset mcp_config.json from global.json (steady state)
# This wipes any previous session's tool state and starts clean.
# =============================================================================
python3 << PYEOF
import json

global_path = "$GLOBAL_PROFILE"
mcp_config_path = "$MCP_CONFIG"

with open(global_path) as f:
    global_cfg = json.load(f)

with open(mcp_config_path, 'w') as f:
    json.dump(global_cfg, f, indent=2)

servers = global_cfg.get("mcpServers", {})
print(f"✓ mcp_config.json reset from global.json — {len(servers)} MCP(s), steady state applied")
PYEOF

# =============================================================================
# STEP 2 — Apply project profile (base always + optional task profile on top)
# Removes declared tools from disabled arrays in mcp_config.json.
# Only declared tools become active — everything else stays disabled.
# =============================================================================
python3 << PYEOF
import json, sys

mcp_config_path = "$MCP_CONFIG"
profile_path = "$PROFILE_FILE"
project_name = "$PROJECT_NAME"
task_profile = "$TASK_PROFILE"

with open(mcp_config_path) as f:
    mcp_config = json.load(f)

with open(profile_path) as f:
    profile = json.load(f)

if "base" not in profile:
    print("Error: [project].json must have a 'base' section.")
    print(f"Found sections: {list(profile.keys())}")
    sys.exit(1)

# Build merged tool allowlist: base + task profile
tools_to_enable = {}
for mcp, tools in profile["base"].items():
    tools_to_enable[mcp] = list(tools)

if task_profile:
    if task_profile not in profile:
        print(f"Warning: task profile '{task_profile}' not found in {profile_path}")
        print(f"Available profiles: {list(profile.keys())}")
        print("Falling back to base profile only.")
        task_profile = ""
    else:
        for mcp, tools in profile[task_profile].items():
            if mcp in tools_to_enable:
                tools_to_enable[mcp] = list(set(tools_to_enable[mcp] + tools))
            else:
                tools_to_enable[mcp] = list(tools)

# Apply: remove declared tools from disabled arrays
servers = mcp_config.get("mcpServers", {})
enabled_summary = []
warnings = []

for mcp_name, tools in tools_to_enable.items():
    if mcp_name not in servers:
        warnings.append(f"  ⚠ '{mcp_name}' in profile but not in mcp_config.json — skipping")
        continue
    disabled_tools = servers[mcp_name].get("disabledTools", [])
    new_disabled_tools = [t for t in disabled_tools if t not in tools]
    servers[mcp_name]["disabledTools"] = new_disabled_tools
    servers[mcp_name]["disabled"] = False
    enabled_summary.append(f"  • {mcp_name}: {tools}")

mcp_config["mcpServers"] = servers

with open(mcp_config_path, 'w') as f:
    json.dump(mcp_config, f, indent=2)

profile_label = "base" + (f" + {task_profile}" if task_profile else "")
print(f"✓ Profile [{profile_label}] applied:")
for line in enabled_summary:
    print(line)
if warnings:
    print("")
    for w in warnings:
        print(w)
PYEOF

echo ""
echo -e "${GREEN}✓ mcp_config.json ready for '${PROJECT_NAME}'${NC}"
echo ""
echo -e "${YELLOW}→ Hit Refresh in the AG MCP panel to activate${NC}"
echo ""
