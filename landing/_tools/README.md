# landing/_tools

Verification tools for the scroll-scrubbed landing pages (written 2026-10-05, see lessons.md "scroll glitches were deterministic layering bugs").
Run from WSL with a login shell (`wsl bash -l ...`); they use the Playwright install in `_tests/runner/node_modules`.
Defaults: `LANDING_ROOT` = `landing/_preview` (set it to `landing/site` for the deployable page), `OUT_DIR` = `/tmp/landing-tools`.

- `exc.js PAGE.html [WxH] [step]`  steps the pinned GSAP timeline in small increments (no scrolling, no seek noise), grabs small screenshots and flags
  A-B-A frame excursions (a layer ghosting through for a moment). Cream flare / cream flood moments are classed "intended". Claim a scroll fix only at 0 REAL.
- `at.js PAGE.html u1,u2,u3 [WxH]`  screenshots at exact timeline positions (u = screens of scroll). Saved under `OUT_DIR/at/`.
- `audit.js PAGE.html [WxH]`  lists which still shows under a fading clip and the stretches where only a still is visible (heuristic, use exc.js as the judge).

Pages must expose `#vclip video`, a pinned ScrollTrigger and `#light` (the flare) as preview-v4.html does.
