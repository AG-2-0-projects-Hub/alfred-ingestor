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
