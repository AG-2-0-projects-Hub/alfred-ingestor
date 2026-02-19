# Global Lessons

## 2026-02-19 — Non-Interactive Shell Tool Visibility
**Context:** Verifying environment tools (git, node, npm, python, claude) in AG.
**Discovery:** nvm and pyenv initialize via .bashrc which only loads in interactive shells. AG spawns non-interactive shells so it can't see node, npm, claude, or python unless permanent symlinks are created in /usr/local/bin.
**Impact:** Fixed by symlinking each tool.
