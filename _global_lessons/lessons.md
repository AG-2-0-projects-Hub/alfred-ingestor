# Global Lessons

## 2026-02-19 — Non-Interactive Shell Tool Visibility
**Context:** Verifying environment tools (git, node, npm, python, claude) in AG.
**Discovery:** nvm and pyenv initialize via .bashrc which only loads in interactive shells. AG spawns non-interactive shells so it can't see node, npm, claude, or python unless permanent symlinks are created in /usr/local/bin.
**Impact:** Fixed by symlinking each tool.

## 2026-02-19 — nvm tools need symlinks for non-interactive access
**Discovery:** Any tool installed via nvm (node, npm, npx, claude) requires 
a symlink to /usr/local/bin/ to be visible to non-interactive processes like 
AG's MCP manager. Complete the full set at install time — don't do them one by one.
**Impact:** Added to Phase 1 setup checklist — symlink all nvm tools immediately after installation.
**Global Candidate:** Yes — applies to every machine setup.

## 2026-02-19 — Agent Manager Path Resolution

**Context:** Antigravity Agent Manager running against AG_master_files workspace in WSL2.

**Discovery:** Agent Manager agents cannot resolve WSL2 paths automatically. They search
Windows drives and relative paths before finding the correct WSL2 location, causing
"directory does not exist" errors even when files are present.

**Fix:** Create `AGENTS.md` at workspace root with explicit absolute WSL2 paths.
Agent Manager reads this file to anchor all filesystem operations.

**Impact:** All Agent Manager sessions now resolve paths correctly from
`/home/santoskoy/AG_master_files/` without manual correction.

**Global Candidate:** Yes — applies to every WSL2 machine setup with Antigravity.

## 2026-02-24 — mcp_config.json lives on Windows side
**Context:** MCP configuration file location in WSL2 environments.
**Discovery:** Path from WSL2: `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json`. Any script targeting it must use this explicit path.
**Impact:** Ensures scripts correctly resolve the out-of-bounds configuration file consistently.
**Global Candidate:** Yes

## 2026-02-24 — Zone.Identifier files are Windows metadata, not AG bugs
**Context:** Resolving `.Zone.Identifier` file clutter.
**Discovery:** These are Windows metadata files, not bugs, and are already blocked by `.gitignore`. Periodic cleanup via Gemini is sufficient. Never apply system-wide registry changes to solve AG-specific cosmetic issues.
**Impact:** Prevents applying destructive Windows Registry changes to resolve cosmetic workspace clutter.
**Global Candidate:** Yes

## 2026-02-24 — Git revert deletes files from filesystem, not just history
**Context:** Reverting file additions.
**Discovery:** Never use `git revert` to undo a file addition without checking what the last commit contained. It removes the file entirely. Always use `git log --oneline` first to verify what you're reverting.
**Impact:** Enforces git safety checks before destructive source control commands.
**Global Candidate:** Yes

## 2026-02-24 — Workspace Boundary Enforcement
**Context:** Operational scope and boundaries of Antigravity on the host OS.
**Discovery:** AG operates exclusively within its own workspace. Never modify system-wide settings, Windows registry, global OS configurations, or any tool/process outside of `~/AG_master_files/`. When a problem exists within AG, solve it within AG. If a fix requires system-wide changes, flag it to the user with explicit warning of scope — never execute it.
**Impact:** Establishes a strict safety boundary to protect the host system from modification.
**Global Candidate:** Constitution Candidate
