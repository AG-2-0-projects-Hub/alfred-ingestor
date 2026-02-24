# Skill Scanner — Trusted Repositories
**Updated:** 2026-02-23

> These are the repos the Skill Scanner is authorized to search and install from.
> Do not install skills from repos not on this list without explicit review.

---

## Primary Sources (Direct Install)

| Repo | URL | Trust Level | Notes |
|---|---|---|---|
| `anthropics/skills` | https://github.com/anthropics/skills | ⭐ Official | Anthropic's own skills — highest trust |
| `obra/superpowers` | https://github.com/obra/superpowers | ⭐ Proven | 20+ battle-tested skills, widely adopted |
| `VoltAgent/awesome-agent-skills` | https://github.com/VoltAgent/awesome-agent-skills | ✅ Verified | 200+ skills, explicitly AG-compatible |

## Discovery Index (Browse Only)

| Repo | URL | Purpose |
|---|---|---|
| `travisvn/awesome-claude-skills` | https://github.com/travisvn/awesome-claude-skills | Curated index — use to find new primary sources |

---

## Retrieval Method

The Skill Scanner uses the **GitHub MCP** (already connected, 26/26 tools active)
to browse and retrieve skills from the repos above.

- Browse repo contents: `github/get_file_contents`
- List available skills: `github/list_directory`
- Install via CLI after review: `npx skills add [repo] --skill [name]`

The GitHub MCP handles authentication automatically via the existing token.

---

## Adding a New Repo

Before adding any repo to Primary Sources:
- [ ] Review at least 3 skills from the repo for quality and safety
- [ ] Confirm it has active maintenance (commits in last 3 months)
- [ ] Check it doesn't duplicate an existing primary source
- [ ] Log the decision in `_global_lessons/lessons.md`

## Removing a Repo

If a repo goes unmaintained or produces stale/broken skills:
- Move it to an `## Archived` section with a reason and date
- Do not delete — preserve the history
