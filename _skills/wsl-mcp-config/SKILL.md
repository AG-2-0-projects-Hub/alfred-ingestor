---
name: wsl-mcp-config
description: Enforce correct MCP configuration patterns for a Windows 11 + WSL2 + Antigravity setup.
---

# WSL MCP Configuration Protocol

## Trigger Scope
This skill applies to **any** task involving installing, modifying, fixing, or verifying an MCP (Model Context Protocol) server or configuration.

## Core Rewrite Rule
AG's MCP manager runs on the Windows host and cannot find `npx` directly. Therefore, all `npx`-based MCPs must route through WSL.

- **Rule:** Any MCP config using `"command": "npx"` must **always** be rewritten to `"command": "wsl"`. The `npx` command itself must be moved into the `args` array.

## Configuration Patterns

### 1. MCPs WITHOUT API Keys
For tools that do not require authentication, simply pass `npx` as the first argument to `wsl`.

```json
{
  "mcpServers": {
    "example-server": {
      "command": "wsl",
      "args": [
        "npx",
        "-y",
        "@example/mcp-server"
      ]
    }
  }
}
```

### 2. MCPs WITH API Keys
API keys must **always** go inline in the `args` array using the `env` command. 
- **NEVER** place API keys in the standard `"env": {}` block of the JSON. Environment variables defined in the `env` block do not forward gracefully through the `wsl` command wrapper.

```json
{
  "mcpServers": {
    "example-secure-server": {
      "command": "wsl",
      "args": [
        "env",
        "EXAMPLE_API_KEY=your_actual_key_here",
        "ANOTHER_VAR=value",
        "npx",
        "-y",
        "@example/secure-mcp-server"
      ]
    }
  }
}
```

## Where the Config Lives
- **AG's MCP settings panel only.** 
- **NEVER** modify `%APPDATA%\\Claude\\claude_desktop_config.json`.
- **NEVER** modify any other random config file on disk natively intended for Claude Desktop or other clients.

## Verification Step
After any MCP change:
1. Restart AG (Antigravity).
2. Confirm the MCP appears in the active tools list with the correct tool count.
