#!/bin/bash
# =============================================================================
# AG New Project Setup Script
# Creates project scaffold, registers scoped Supabase MCP, generates MCP profile
# Usage: bash ~/AG_master_files/_scripts/new-project.sh
# =============================================================================

set -e

# --- Preflight Check ---
for cmd in node npm npx claude; do
  if [[ ! -x "/usr/local/bin/$cmd" ]]; then
    echo -e "\033[0;31mError: $cmd not found in /usr/local/bin. Have you run the nvm symlinks step?\033[0m"
    exit 1
  fi
done

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
mkdir -p "$PROJECT_DIR/_mcp"
touch "$PROJECT_DIR/_mcp/project_mcps.md"
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/.vscode"

cat > "$PROJECT_DIR/.vscode/tasks.json" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Sync AG MCP Profile",
      "type": "shell",
      "command": "bash ~/AG_master_files/_scripts/ag-switch.sh",
      "runOptions": {
        "runOn": "folderOpen"
      },
      "presentation": {
        "echo": true,
        "reveal": "never",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": true
      }
    }
  ]
}
EOF

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

# --- Step 4: Register scoped Supabase MCP in mcp_config.json ---
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo ""
  echo -e "Registering scoped Supabase MCP..."

  if [[ ! -f "$MCP_CONFIG" ]]; then
    echo -e "${RED}Error: MCP config not found at: $MCP_CONFIG${NC}"
    echo -e "${YELLOW}Add this entry manually to mcp_config.json:${NC}"
    echo ""
    echo "\"${MCP_NAME}\": {"
    echo "  \"command\": \"wsl\","
    echo "  \"args\": [\"env\", \"SUPABASE_ACCESS_TOKEN=<your-token>\", \"npx\", \"-y\", \"@supabase/mcp-server-supabase@latest\", \"--project-ref=${SUPABASE_PROJECT_REF}\"]"
    echo "}"
  else
    python3 << PYEOF
import json, sys

config_path = "${MCP_CONFIG}"
mcp_name = "${MCP_NAME}"
project_ref = "${SUPABASE_PROJECT_REF}"

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Error reading mcp_config.json: {e}")
    sys.exit(1)

if "mcpServers" not in config:
    print("Error: mcpServers block not found in mcp_config.json.")
    sys.exit(1)

# Inherit token from global supabase entry
token = None
for arg in config["mcpServers"].get("supabase", {}).get("args", []):
    if arg.startswith("SUPABASE_ACCESS_TOKEN="):
        token = arg.split("=", 1)[1]
        break

if not token:
    print("Error: SUPABASE_ACCESS_TOKEN not found in global supabase entry. Configure it first.")
    sys.exit(1)

if mcp_name in config["mcpServers"]:
    print(f"Warning: {mcp_name} already exists — skipping.")
else:
    config["mcpServers"][mcp_name] = {
        "command": "wsl",
        "args": ["env", f"SUPABASE_ACCESS_TOKEN={token}", "npx", "-y",
                 "@supabase/mcp-server-supabase@latest", f"--project-ref={project_ref}"]
    }
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"ok: added '{mcp_name}' to mcp_config.json")
    print("Note: global.json will absorb this entry automatically on next ag-switch run.")
PYEOF

    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}✓ Added '${MCP_NAME}' to mcp_config.json${NC}"
    fi
  fi
fi

# --- Step 5: Generate MCP profile (named profiles structure) ---
echo ""
echo -e "Setting up MCP profile..."
mkdir -p "$PROFILES_DIR"

# Show available MCPs
if [[ -f "$GLOBAL_PROFILE" ]]; then
  echo ""
  echo -e "${CYAN}Available MCPs (from global.json):${NC}"
  python3 -c "
import json
with open('$GLOBAL_PROFILE') as f:
    cfg = json.load(f)
servers = list(cfg.get('mcpServers', {}).keys())
for i, s in enumerate(servers, 1):
    print(f'  {i}. {s}')
"
elif [[ -f "$MCP_CONFIG" ]]; then
  echo ""
  echo -e "${CYAN}Available MCPs (from mcp_config.json):${NC}"
  python3 -c "
import json
with open('$MCP_CONFIG') as f:
    cfg = json.load(f)
servers = list(cfg.get('mcpServers', {}).keys())
for i, s in enumerate(servers, 1):
    print(f'  {i}. {s}')
"
fi

echo ""
echo -e "${YELLOW}Which MCPs does this project need for its BASE profile?${NC}"
echo -e "Enter MCP names separated by spaces (e.g. context7 github notion)"
if [[ -n "$MCP_NAME" ]]; then
  echo -e "${CYAN}Note: ${MCP_NAME} will be added automatically (Supabase scoped)${NC}"
fi
echo ""
read -p "Base MCPs: " BASE_MCPS_INPUT

# Build named profile JSON
python3 << PYEOF
import json, sys, os

profiles_dir = "$PROFILES_DIR"
project_name = "$PROJECT_NAME"
mcp_name = "$MCP_NAME"
global_path = "$GLOBAL_PROFILE"
mcp_config_path = "$MCP_CONFIG"
base_input = "$BASE_MCPS_INPUT"

# Parse selected base MCPs
base_mcps = [s.strip() for s in base_input.split() if s.strip()]

# Always include scoped Supabase MCP if created
if mcp_name and mcp_name not in base_mcps:
    base_mcps.append(mcp_name)

# Validate against available MCPs
ref_path = global_path if os.path.exists(global_path) else mcp_config_path
if os.path.exists(ref_path):
    with open(ref_path) as f:
        ref_cfg = json.load(f)
    available = list(ref_cfg.get("mcpServers", {}).keys())
    invalid = [s for s in base_mcps if s not in available]
    if invalid:
        print(f"Warning: these MCPs are not available and will be skipped: {invalid}")
        base_mcps = [s for s in base_mcps if s in available]

if not base_mcps:
    print("Warning: no valid MCPs selected. Profile will have an empty base.")

# Build profile with base section only (task profiles added later via mcp-tool-manager)
profile = {
    "base": {mcp: [] for mcp in base_mcps}
}

profile_path = os.path.join(profiles_dir, f"{project_name}.json")
with open(profile_path, 'w') as f:
    json.dump(profile, f, indent=2)

print(f"✓ Profile created: _mcp_profiles/{project_name}.json")
print(f"  Base MCPs: {base_mcps}")
print(f"  Note: Tool allowlists are empty — run mcp-tool-manager to define which tools to enable.")
PYEOF

echo -e "${GREEN}✓ MCP profile created: _mcp_profiles/${PROJECT_NAME}.json${NC}"
echo -e "${YELLOW}  Run mcp-tool-manager skill after kickoff to populate tool allowlists.${NC}"

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
echo -e "  1. ${YELLOW}Restart AG${NC} to activate new MCP connections"
echo -e "  2. Open: ${CYAN}projects/${PROJECT_NAME}/${NC} in VS Code"
echo -e "  3. ${YELLOW}Hit Refresh${NC} in the MCP panel (tasks.json auto-fires ag-switch)"
echo -e "  4. Run BLAST Phase 1 (Blueprint)"
echo -e "  5. Run ${CYAN}mcp-tool-manager${NC} skill to define tool allowlists for this project"
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo ""
  echo -e "Supabase MCP: ${CYAN}${MCP_NAME}${NC} scoped to project_ref: ${CYAN}${SUPABASE_PROJECT_REF}${NC}"
fi
echo ""
