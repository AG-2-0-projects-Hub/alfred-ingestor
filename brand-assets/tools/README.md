# brand-assets/tools: scripts that worked on 2026-10-02 (copied from the session scratchpad, minimal and tested)
- `vertex_image_smoke.py` — Nano Banana image generation through Vertex ADC. Run from `backend/venv` with `TOKEN=$(~/google-cloud-sdk/bin/gcloud auth print-access-token) python vertex_image_smoke.py out.png`. Project `alfred-prod-502215`, location `global`, model `gemini-3-pro-image`. Fixed prompt: extend it for the brandkit board / asset pack (reference-image anchoring is untested).
- `openrouter_bakeoff.py` — 3 tasks x N cheap models via OpenRouter; reads `OPENROUTER_API_KEY` from root `_scripts/.env` (never prints it). Usage: `python openrouter_bakeoff.py <scratch_dir_with_competitor.png> model1,model2`.
- `contrast_check.py` — WCAG contrast of palette token pairs (edit the dicts at the top).
Run order/quoting gotcha: PowerShell `wsl bash -lc '...;...'` splits on `;` — put commands in a script file and run `wsl bash -l /mnt/c/.../script.sh`.
