# Mayordommo brand-asset manifest (2026-10-02)

Engine for every image: Vertex ADC, `gemini-3-pro-image`, location `global`, project `alfred-prod-502215`, 2K 16:9 (2752x1536), one asset per prompt, style DNA + palette + exclusions verbatim in each prompt (`prompts/`). Price used: $0.134 per 1K/2K image (Google Cloud pricing page, checked 2026-10-02). Scripts: `tools/vertex_image.py` (single), `tools/gen_pack.py` (images 2-10). Founder-approved total for the pack: ~$1.35, cap ~$1.75.

| # | Master (PNG) | Web (WebP, full / 1280w in `web/`) | Prompt | Notes |
|---|---|---|---|---|
| 1 | `banner/hero-courtyard-dusk.png` (cropped 2560x1440; uncropped original `hero-courtyard-dusk-full.png`) | `web/hero-courtyard-dusk.webp` | `prompts/01-hero-courtyard-dusk.txt` | Anchor. Camera fixture cropped out at the founder's request. |
| 2 | `heroes/casita-costa-noche.png` | `web/casita-costa-noche.webp` | `prompts/02-...` | Cycladic arch beach house |
| 3 | `heroes/loft-cdmx-noche.png` | `web/loft-cdmx-noche.webp` | `prompts/03-...` | Mexico City street door |
| 4 | `action/llave-en-puerta.png` | `web/llave-en-puerta.webp` | `prompts/04-...` | Hand-off moment |
| 5 | `action/telefono-boca-abajo.png` | `web/telefono-boca-abajo.webp` | `prompts/05-...` | "Regálate tiempo" |
| 6 | `detail/llave-laton-lino.png` | `web/llave-laton-lino.webp` | `prompts/06-...` | Regenerated once (first take had pink/brown linen: red 8% vs 0%); rejected take in `_rejected/` |
| 7 | `detail/farol-pared.png` | `web/farol-pared.webp` | `prompts/07-...` | Empty left for headline |
| 8 | `lifestyle/huesped-llega.png` | `web/huesped-llega.webp` | `prompts/08-...` | Guest from behind |
| 9 | `lifestyle/anfitrion-terraza.png` | `web/anfitrion-terraza.webp` | `prompts/09-...` | Host's hands; first two attempts hit Vertex 429 (quota), third succeeded |
| 10 | `extras/tarjeta-puerta-oro.png` | `web/tarjeta-puerta-oro.webp` | `prompts/10-...` | Door-hanger, refs: logo (light) + board crop |

Spend: pack = 11 images (10 + 1 regeneration) × $0.134 = **$1.47** (inside the $1.75 cap). Earlier drafts (not part of the pack): 2 concept boards + 2 photo contact sheets = 4 × $0.134 = $0.54, kept in `concept/`. Total image spend this session ≈ **$2.01** (list price, billed to the GCP credit; the 429 failures should not bill, not verified on the billing page).

## QA of the set (2026-10-02)
- **Consistency:** one violet-night world, one warm practical light, same grain and grade across all ten (checked by eye on every frame).
- **Palette adherence (sampled):** median tone of every night frame is aubergine/plum violet (e.g. #361C43, #2C1C39, #14101F); sky samples match Lilac Mist (#BDABD7 vs #BCA9D5); the lit areas are the same hue as Lantern Gold but more saturated (#F6AA21 vs #F4B64C) because they are light sources. Red/terracotta-red pixels ≤ 4.4% in every frame (the loft door's warm wood); none has a red wall band. Door-hanger (#10) median is walnut wood by design (print extra, not part of the night palette).
- **Anti-generic:** no text, logos, faces, neon, sparkles or security cameras in frame.
- **Known soft spots (accepted):** phone in #5 and #9 reads screen-up (glossy black), not strictly face-down; the hills in #9 look Tuscan more than Mexican.
