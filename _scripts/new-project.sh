#!/bin/bash
# =============================================================================
# AG New Project Setup Script
# Creates project scaffold and optionally registers a scoped Supabase MCP
# Usage: bash ~/AG_master_files/_scripts/new-project.sh
# =============================================================================

set -e

# --- Config ---
AG_ROOT="$HOME/AG_master_files"
TEMPLATE_DIR="$AG_ROOT/projects/_template"
PROJECTS_DIR="$AG_ROOT/projects"
MCP_CONFIG="/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Populate CLAUDE.md with project name and stack info
cat > "$PROJECT_DIR/CLAUDE.md" << EOF
# ${PROJECT_NAME} — Local Law

**Inherits:** AG Global Constitution (GEMINI.md)
**Overrides:** None
**Stack:** [Define after BLAST Blueprint phase]
**Data Schema:** [Define after BLAST Blueprint phase]
EOF

# Add Supabase section to CLAUDE.md if needed
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
cat >> "$PROJECT_DIR/CLAUDE.md" << EOF

## Supabase Connection
**MCP name:** \`${MCP_NAME}\`
**Scoped to this project only.**
Use ONLY this MCP for all database operations in this project.
Never use the global \`supabase\` MCP when working inside this project.
EOF
fi

# Populate CONTEXT.md with creation date
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

# --- Step 4: Register scoped MCP (if Supabase needed) ---
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo ""
  echo -e "Registering scoped Supabase MCP..."

  if [[ ! -f "$MCP_CONFIG" ]]; then
    echo -e "${RED}Error: MCP config not found at: $MCP_CONFIG${NC}"
    echo -e "${YELLOW}Attempting to locate it...${NC}"
    FOUND=$(find /mnt/c/Users -name "mcp_config.json" 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
      echo -e "${YELLOW}Found at: $FOUND${NC}"
      echo -e "${YELLOW}Update the MCP_CONFIG variable in this script to that path, then re-run.${NC}"
    else
      echo -e "${RED}Could not locate mcp_config.json. Add the MCP entry manually (see below).${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Manual entry to add to your MCP config:${NC}"
    echo ""
    echo "\"${MCP_NAME}\": {"
    echo "  \"type\": \"http\","
    echo "  \"url\": \"https://mcp.supabase.com/mcp?project_ref=${SUPABASE_PROJECT_REF}\""
    echo "}"
    echo ""
  else
    # Use Python to safely inject the new MCP entry into the JSON
    python3 << PYEOF
import json
import sys

config_path = "${MCP_CONFIG}"
mcp_name = "${MCP_NAME}"
project_ref = "${SUPABASE_PROJECT_REF}"

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Error reading config: {e}")
    sys.exit(1)

if "mcpServers" not in config:
    config["mcpServers"] = {}

if mcp_name in config["mcpServers"]:
    print(f"Warning: {mcp_name} already exists in MCP config — skipping.")
else:
    config["mcpServers"][mcp_name] = {
        "type": "http",
        "url": f"https://mcp.supabase.com/mcp?project_ref={project_ref}"
    }
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"ok")
PYEOF

    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}✓ Added '${MCP_NAME}' to MCP config${NC}"
    fi
  fi
fi

# --- Step 5: Git commit the new project scaffold ---
echo ""
echo -e "Committing to git..."
cd "$AG_ROOT"
git add "projects/${PROJECT_NAME}/"
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
echo -e "  3. Run BLAST Phase 1 (Blueprint) to define stack and schema"
echo ""
if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
  echo -e "Supabase MCP registered as: ${CYAN}${MCP_NAME}${NC}"
  echo -e "Scoped to project_ref: ${CYAN}${SUPABASE_PROJECT_REF}${NC}"
  echo ""
fi
