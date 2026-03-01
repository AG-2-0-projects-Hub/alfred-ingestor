#!/bin/bash
# =============================================================================
# AG Switch — MCP Profile Switcher
# Activates the MCP profile for the current project (or a named one)
# Usage:
#   bash ~/AG_master_files/_scripts/ag-switch.sh            ← auto-detect from CLAUDE.md
#   bash ~/AG_master_files/_scripts/ag-switch.sh alfred     ← explicit project name
#   bash ~/AG_master_files/_scripts/ag-switch.sh --add-mcp context7      ← add MCP to current project
#   bash ~/AG_master_files/_scripts/ag-switch.sh --remove-mcp context7   ← remove MCP from current project
#   bash ~/AG_master_files/_scripts/ag-switch.sh --list     ← show current profile
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
if [[ ! -f "$GLOBAL_PROFILE" ]]; then
  echo -e "${RED}Error: global.json not found at $GLOBAL_PROFILE${NC}"
  echo -e "${YELLOW}Run: cp $MCP_CONFIG $GLOBAL_PROFILE${NC}"
  exit 1
fi

if [[ ! -f "$MCP_CONFIG" ]]; then
  echo -e "${RED}Error: mcp_config.json not found at $MCP_CONFIG${NC}"
  exit 1
fi

# --- Detect project name ---
# Priority: explicit arg > CLAUDE.md in current dir > CLAUDE.md walk-up
detect_project() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/CLAUDE.md" ]]; then
      # Extract project name from first heading: "# [project-name] — Local Law"
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

# --- Handle flags ---
case "$1" in
  --list)
    CURRENT=$(python3 -c "
import json
try:
    with open('$MCP_CONFIG') as f:
        c = json.load(f)
    servers = list(c.get('mcpServers', {}).keys())
    print('Active MCPs (' + str(len(servers)) + '):')
    for s in servers:
        print('  • ' + s)
except Exception as e:
    print('Error: ' + str(e))
")
    echo -e "${CYAN}$CURRENT${NC}"
    exit 0
    ;;

  --add-mcp)
    MCP_TO_ADD="$2"
    if [[ -z "$MCP_TO_ADD" ]]; then
      echo -e "${RED}Error: specify MCP name. e.g. --add-mcp context7${NC}"
      exit 1
    fi
    PROJECT_NAME=$(detect_project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_NAME" ]]; then
      echo -e "${RED}Error: could not detect project. Navigate to a project folder.${NC}"
      exit 1
    fi
    PROFILE_FILE="$PROFILES_DIR/${PROJECT_NAME}.json"
    if [[ ! -f "$PROFILE_FILE" ]]; then
      echo -e "${RED}Error: no profile found for '$PROJECT_NAME'${NC}"
      exit 1
    fi
    python3 << PYEOF
import json, sys

global_path = "$GLOBAL_PROFILE"
profile_path = "$PROFILE_FILE"
mcp_to_add = "$MCP_TO_ADD"

with open(global_path) as f:
    global_cfg = json.load(f)

with open(profile_path) as f:
    profile = json.load(f)

if mcp_to_add not in global_cfg.get("mcpServers", {}):
    print(f"Error: '{mcp_to_add}' not found in global.json. Add it to global first.")
    sys.exit(1)

if mcp_to_add in profile.get("mcpServers", []):
    print(f"'{mcp_to_add}' already in this project's profile.")
    sys.exit(0)

profile.setdefault("mcpServers", []).append(mcp_to_add)
with open(profile_path, 'w') as f:
    json.dump(profile, f, indent=2)
print(f"ok: added '{mcp_to_add}' to {profile_path}")
PYEOF
    echo -e "${GREEN}✓ Added '$MCP_TO_ADD' to ${PROJECT_NAME} profile${NC}"
    echo -e "${YELLOW}Re-running ag-switch to reload...${NC}"
    exec "$0" "$PROJECT_NAME"
    ;;

  --remove-mcp)
    MCP_TO_REMOVE="$2"
    if [[ -z "$MCP_TO_REMOVE" ]]; then
      echo -e "${RED}Error: specify MCP name. e.g. --remove-mcp context7${NC}"
      exit 1
    fi
    PROJECT_NAME=$(detect_project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_NAME" ]]; then
      echo -e "${RED}Error: could not detect project.${NC}"
      exit 1
    fi
    PROFILE_FILE="$PROFILES_DIR/${PROJECT_NAME}.json"
    python3 << PYEOF
import json, sys

profile_path = "$PROFILE_FILE"
mcp_to_remove = "$MCP_TO_REMOVE"

with open(profile_path) as f:
    profile = json.load(f)

servers = profile.get("mcpServers", [])
if mcp_to_remove not in servers:
    print(f"'{mcp_to_remove}' not in this project's profile.")
    sys.exit(0)

profile["mcpServers"] = [s for s in servers if s != mcp_to_remove]
with open(profile_path, 'w') as f:
    json.dump(profile, f, indent=2)
print(f"ok: removed '{mcp_to_remove}'")
PYEOF
    echo -e "${GREEN}✓ Removed '$MCP_TO_REMOVE' from ${PROJECT_NAME} profile${NC}"
    echo -e "${YELLOW}Re-running ag-switch to reload...${NC}"
    exec "$0" "$PROJECT_NAME"
    ;;
esac

# --- Resolve project name ---
if [[ -n "$1" ]]; then
  PROJECT_NAME="$1"
else
  PROJECT_NAME=$(detect_project 2>/dev/null || echo "")
  if [[ -z "$PROJECT_NAME" ]]; then
    # Check if we are at AG root level specifically
    if [[ "$PWD" == "$AG_ROOT" || "$PWD" == "$HOME/AG_master_files" ]]; then
      echo -e "${YELLOW}You are at the AG root level.${NC}"
      echo -e "${YELLOW}ag-switch only runs inside a project folder.${NC}"
      echo -e "${YELLOW}Open a project folder first, or pass the name explicitly:${NC}"
      echo -e "  bash ag-switch.sh alfred"
    else
      echo -e "${RED}Error: could not detect project from CLAUDE.md.${NC}"
      echo -e "${YELLOW}Navigate to a project folder or pass the name explicitly:${NC}"
      echo -e "  bash ag-switch.sh alfred"
    fi
    exit 1
  fi
fi

PROFILE_FILE="$PROFILES_DIR/${PROJECT_NAME}.json"

if [[ ! -f "$PROFILE_FILE" ]]; then
  echo -e "${RED}Error: no profile found for '$PROJECT_NAME' at $PROFILE_FILE${NC}"
  echo -e "${YELLOW}Create one with new-project.sh, or manually create $PROFILE_FILE${NC}"
  exit 1
fi

echo ""
echo -e "${CYAN}=======================================${NC}"
echo -e "${CYAN}   AG Switch → ${PROJECT_NAME}${NC}"
echo -e "${CYAN}=======================================${NC}"
echo ""

# --- Step 1: Sync mcp_config.json → global.json (mcp_config is source of truth) ---
python3 << PYEOF
import json, sys, os

mcp_config_path = "$MCP_CONFIG"
global_path = "$GLOBAL_PROFILE"

try:
    with open(mcp_config_path) as f:
        mcp_config = json.load(f)
except Exception as e:
    print(f"Error reading mcp_config.json: {e}")
    sys.exit(1)

global_cfg = {}
if os.path.exists(global_path):
    try:
        with open(global_path) as f:
            global_cfg = json.load(f)
    except:
        pass

global_cfg["mcpServers"] = mcp_config.get("mcpServers", {})

with open(global_path, 'w') as f:
    json.dump(global_cfg, f, indent=2)
print(f"✓ global.json synced ({len(global_cfg['mcpServers'])} MCPs)")
PYEOF

# --- Step 2: Build scoped mcp_config.json from project profile + keys in global ---
python3 << PYEOF
import json, sys

global_path = "$GLOBAL_PROFILE"
profile_path = "$PROFILE_FILE"
output_path = "$MCP_CONFIG"
project_name = "$PROJECT_NAME"

try:
    with open(global_path) as f:
        global_cfg = json.load(f)
except Exception as e:
    print(f"Error reading global.json: {e}")
    sys.exit(1)

try:
    with open(profile_path) as f:
        profile = json.load(f)
except Exception as e:
    print(f"Error reading profile: {e}")
    sys.exit(1)

requested = profile.get("mcpServers", [])
global_servers = global_cfg.get("mcpServers", {})

output = {"mcpServers": {}}
missing = []

for mcp_name in requested:
    if mcp_name in global_servers:
        output["mcpServers"][mcp_name] = global_servers[mcp_name]
    else:
        missing.append(mcp_name)

if missing:
    print(f"Warning: these MCPs are in the profile but not in global.json: {missing}")
    print("They will be skipped. Add them via the AG MCP panel first.")

with open(output_path, 'w') as f:
    json.dump(output, f, indent=2)

server_list = list(output["mcpServers"].keys())
print(f"Activated {len(server_list)} MCPs for '{project_name}':")
for s in server_list:
    print(f"  • {s}")
PYEOF

echo ""
echo -e "${GREEN}✓ mcp_config.json updated for '${PROJECT_NAME}'${NC}"
echo ""
echo -e "${YELLOW}→ Hit Refresh in the AG MCP panel to activate${NC}"
echo ""
