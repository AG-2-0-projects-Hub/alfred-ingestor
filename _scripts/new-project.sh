#!/bin/bash
# =============================================================================
# AG New Project Setup Script
# Creates project scaffold, registers scoped Supabase MCP, generates MCP profile
# Usage: bash ~/AG_master_files/_scripts/new-project.sh
# =============================================================================

set -e

# --- Config ---
AG_ROOT="$HOME/AG_master_files"
TEMPLATE_DIR="$AG_ROOT/projects/_template"
PROJECTS_DIR="$AG_ROOT/projects"
PROFILES_DIR="$AG_ROOT/_mcp_profiles"
GLOBAL_PROFILE="$PROFILES_DIR/global.json"
MCP_CONFIG="/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=======================================${NC}"
echo -e "${CYAN}   AG New Project Setup               ${NC}"
echo -e "${CYAN}=======================================${NC}"
echo ""

# --- Step 1: Project name ---
read -p "Project name (lowercase, no spaces — e.g. alfred, projectx): " PROJECT_NAME

if [[ -z "$PROJECT_NAME" ]]; then
  echo -e "${RED}Error: Project name cannot be empty.${NC}"
  exit 1
fi

if [[ ! "$PROJECT_NAME" =~ ^[a-z0-9_-]+$ ]]; then
  echo -e "${RED}Error: Use only lowercase letters, numbers, hyphens, or underscores.${NC}"
  exit 1
fi

PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"

if [[ -d "$PROJECT_DIR" ]]; then
  echo -e "${RED}Error: Project '$PROJECT_NAME' already exists at $PROJECT_DIR${NC}"
  exit 1
fi

# --- Step 2: Supabase? ---
echo ""
read -p "Does this project need a Supabase database? (y/n): " NEEDS_SUPABASE

SUPABASE_PROJECT_REF=""
MCP_NAME=""

if [[ "$NEEDS_SUPABASE" == "y" || "$NEEDS_SUPABASE" == "Y" ]]; then
  echo ""
  echo -e "${YELLOW}Find your project_ref in Supabase Dashboard → Project Settings → General → Project ID${NC}"
  echo -e "${YELLOW}It's a 20-character string like: abcdefghijklmnopqrst${NC}"
  echo ""
  read -p "Supabase project_ref: " SUPABASE_PROJECT_REF

  if [[ -z "$SUPABASE_PROJECT_REF" ]]; then
    echo -e "${RED}Error: project_ref cannot be empty if Supabase is needed.${NC}"
    exit 1
  fi

  MCP_NAME="supabase-${PROJECT_NAME}"
fi

# --- Step 3: Scaffold project folder ---
echo ""
echo -e "Creating project scaffold..."

cp -r "$TEMPLATE_DIR" "$PROJECT_DIR"

cat > "$PROJECT_DIR/CLAUDE.md" << EOF
# ${PROJECT_NAME} — Local Law

**Active Workspace:** \`projects/${PROJECT_NAME}/\` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** AG Global Constitution (GEMINI.md)
**Overrides:** None
**Stack:** [Define after BLAST Blueprint phase]
**Data Schema:** [Define after BLAST Blueprint phase]
EOF

if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
cat >> "$PROJECT_DIR/CLAUDE.md" << EOF

## Supabase Connection
**MCP name:** \`${MCP_NAME}\`
**project_ref:** \`${SUPABASE_PROJECT_REF}\`
**Scoped to this project only.**
Use ONLY this MCP for all database operations in this project.
Never use the global \`supabase\` MCP when working inside this project.
EOF
fi

cat > "$PROJECT_DIR/CONTEXT.md" << EOF
# Session Context
**Created:** $(date '+%Y-%m-%d')
**Last Session:** —
**Accomplished:** Project scaffolded
**Pending:** Run BLAST Phase 1 (Blueprint)
**Unresolved Decisions:** —
EOF

echo -e "${GREEN}✓ Created projects/${PROJECT_NAME}/${NC}"
echo -e "${GREEN}✓ CLAUDE.md, CONTEXT.md, lessons.md populated${NC}"

# --- Step 4: Register scoped Supabase MCP in global.json + mcp_config.json ---
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo ""
  echo -e "Registering scoped Supabase MCP..."

  if [[ ! -f "$MCP_CONFIG" ]]; then
    echo -e "${RED}Error: MCP config not found at: $MCP_CONFIG${NC}"
    echo -e "${YELLOW}Add this entry manually to your MCP config and global.json:${NC}"
    echo ""
    echo "\"${MCP_NAME}\": {"
    echo "  \"command\": \"wsl\","
    echo "  \"args\": [\"env\", \"SUPABASE_ACCESS_TOKEN=<your-token>\", \"npx\", \"-y\", \"@supabase/mcp-server-supabase@latest\", \"--project-ref=${SUPABASE_PROJECT_REF}\"]"
    echo "}"
  else
    python3 << PYEOF
import json, sys

config_path = "${MCP_CONFIG}"
global_path = "${GLOBAL_PROFILE}"
mcp_name = "${MCP_NAME}"
project_ref = "${SUPABASE_PROJECT_REF}"

def add_supabase_entry(cfg, mcp_name, project_ref):
    """Add scoped supabase entry, inheriting token from global supabase entry."""
    token = None
    for arg in cfg["mcpServers"].get("supabase", {}).get("args", []):
        if arg.startswith("SUPABASE_ACCESS_TOKEN="):
            token = arg.split("=", 1)[1]
            break

    if not token:
        print("Error: SUPABASE_ACCESS_TOKEN not found in global supabase entry. Configure it first.")
        sys.exit(1)

    if mcp_name in cfg["mcpServers"]:
        print(f"Warning: {mcp_name} already exists — skipping.")
        return False

    cfg["mcpServers"][mcp_name] = {
        "command": "wsl",
        "args": ["env", f"SUPABASE_ACCESS_TOKEN={token}", "npx", "-y",
                 "@supabase/mcp-server-supabase@latest", f"--project-ref={project_ref}"]
    }
    return True

# Add to mcp_config.json
try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Error reading mcp_config.json: {e}")
    sys.exit(1)

if "mcpServers" not in config:
    print("Error: mcpServers block not found in mcp_config.json.")
    sys.exit(1)

added = add_supabase_entry(config, mcp_name, project_ref)
if added:
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"ok_config")

# Add to global.json (source of truth)
if "${GLOBAL_PROFILE}" and __import__('os').path.exists("${GLOBAL_PROFILE}"):
    try:
        with open(global_path, 'r') as f:
            global_cfg = json.load(f)
        if "mcpServers" not in global_cfg:
            global_cfg["mcpServers"] = {}
        if mcp_name not in global_cfg["mcpServers"]:
            # Re-read token from global_cfg itself (it's the master)
            token = None
            for arg in global_cfg["mcpServers"].get("supabase", {}).get("args", []):
                if arg.startswith("SUPABASE_ACCESS_TOKEN="):
                    token = arg.split("=", 1)[1]
                    break
            if token:
                global_cfg["mcpServers"][mcp_name] = {
                    "command": "wsl",
                    "args": ["env", f"SUPABASE_ACCESS_TOKEN={token}", "npx", "-y",
                             "@supabase/mcp-server-supabase@latest", f"--project-ref={project_ref}"]
                }
                with open(global_path, 'w') as f:
                    json.dump(global_cfg, f, indent=2)
                print("ok_global")
    except Exception as e:
        print(f"Warning: could not update global.json: {e}")
PYEOF

    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}✓ Added '${MCP_NAME}' to mcp_config.json and global.json${NC}"
    fi
  fi
fi

# --- Step 5: Generate MCP profile ---
echo ""
echo -e "Setting up MCP profile..."

# Ensure profiles dir exists
mkdir -p "$PROFILES_DIR"

# Check if global.json exists
if [[ ! -f "$GLOBAL_PROFILE" ]]; then
  echo -e "${YELLOW}global.json not found. Creating from current mcp_config.json...${NC}"
  if [[ -f "$MCP_CONFIG" ]]; then
    cp "$MCP_CONFIG" "$GLOBAL_PROFILE"
    echo -e "${GREEN}✓ Created global.json from mcp_config.json${NC}"
    echo -e "${YELLOW}Note: global.json is gitignored (contains API keys). Back it up manually.${NC}"
  else
    echo -e "${RED}Warning: mcp_config.json not found. Create global.json manually at:${NC}"
    echo -e "  $GLOBAL_PROFILE"
  fi
fi

# Show available MCPs from global.json
if [[ -f "$GLOBAL_PROFILE" ]]; then
  echo ""
  echo -e "${CYAN}Available MCPs in global.json:${NC}"
  python3 -c "
import json
with open('$GLOBAL_PROFILE') as f:
    cfg = json.load(f)
servers = list(cfg.get('mcpServers', {}).keys())
for i, s in enumerate(servers, 1):
    print(f'  {i}. {s}')
"
fi

echo ""
echo -e "${YELLOW}Which MCPs does this project need?${NC}"
echo -e "Enter MCP names separated by spaces (e.g. context7 github notion)"
if [[ -n "$MCP_NAME" ]]; then
  echo -e "${CYAN}Note: ${MCP_NAME} will be added automatically (Supabase scoped)${NC}"
fi
echo ""
read -p "MCPs for this project: " SELECTED_MCPS_INPUT

# Build the profile JSON
python3 << PYEOF
import json, sys, os

profiles_dir = "$PROFILES_DIR"
project_name = "$PROJECT_NAME"
mcp_name = "$MCP_NAME"
global_path = "$GLOBAL_PROFILE"
selected_input = "$SELECTED_MCPS_INPUT"

# Parse selected MCPs
selected = [s.strip() for s in selected_input.split() if s.strip()]

# Always include scoped Supabase MCP if created
if mcp_name and mcp_name not in selected:
    selected.append(mcp_name)

# Validate against global.json
if os.path.exists(global_path):
    with open(global_path) as f:
        global_cfg = json.load(f)
    available = list(global_cfg.get("mcpServers", {}).keys())
    invalid = [s for s in selected if s not in available]
    if invalid:
        print(f"Warning: these MCPs are not in global.json and will be skipped: {invalid}")
        selected = [s for s in selected if s in available]

if not selected:
    print("Warning: no valid MCPs selected. Profile will be empty.")

profile = {"mcpServers": selected}
profile_path = os.path.join(profiles_dir, f"{project_name}.json")

with open(profile_path, 'w') as f:
    json.dump(profile, f, indent=2)

print(f"Profile created with {len(selected)} MCPs:")
for s in selected:
    print(f"  • {s}")
PYEOF

echo -e "${GREEN}✓ MCP profile created: _mcp_profiles/${PROJECT_NAME}.json${NC}"

# --- Step 6: Git commit ---
echo ""
echo -e "Committing to git..."
cd "$AG_ROOT"
git add "projects/${PROJECT_NAME}/" "_mcp_profiles/${PROJECT_NAME}.json"
git commit -m "Scaffold: new project '${PROJECT_NAME}'"
git push
echo -e "${GREEN}✓ Pushed to GitHub${NC}"

# --- Done ---
echo ""
echo -e "${CYAN}=======================================${NC}"
echo -e "${GREEN}  Project '${PROJECT_NAME}' is ready!${NC}"
echo -e "${CYAN}=======================================${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. ${YELLOW}Restart AG${NC} to activate the new MCP connection"
echo -e "  2. Open: ${CYAN}projects/${PROJECT_NAME}/${NC}"
echo -e "  3. ${YELLOW}Run:${NC} bash ~/AG_master_files/_scripts/ag-switch.sh"
echo -e "     Then hit ${YELLOW}Refresh${NC} in the MCP panel"
echo -e "  4. Run BLAST Phase 1 (Blueprint) to define stack and schema"
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo ""
  echo -e "Supabase MCP: ${CYAN}${MCP_NAME}${NC} scoped to project_ref: ${CYAN}${SUPABASE_PROJECT_REF}${NC}"
fi
echo ""
