# Mayordommo — Custom Asset Plan (Brand Protocol Step 5) — PENDING FOUNDER APPROVAL

Engine: Vertex ADC, `gemini-3-pro-image`, location `global`, project `alfred-prod-502215` (script `brand-assets/tools/vertex_image.py`). Price source: Google Cloud Agent Platform pricing page, checked 2026-10-02: **$0.134 per 1K/2K output image** ($0.24 at 4K, not used), ~$0.001 per input reference image. Everything is generated at 2K 16:9 (2752x1536, the same price as 1K), exported to WebP for the web.

Not generated, on purpose (saves money, rule 7 "no text baked in"): the logo (locked SVGs already exist), wordmark and tagline (real Cormorant Garamond 700 type), textures/glow overlays (CSS/SVG noise in code), swatch/typography boards (live in `DESIGN.md`/brand-preview).

## Style DNA (fixed for the whole run, appended verbatim to every prompt)
Cinematic night photography lit by one warm lantern-gold practical light (#F4B64C) visible in or near the frame, spilling softly onto plaster, stone and aged wood; all other areas fall into deep aubergine-violet dusk shadow (#160C24, #25153C), no fill, no rim light. Matte materials with visible grain: stucco, terracotta, linen, brass. 35mm lens, shallow depth of field, eye level, subject off-centre on a third. Warm gold highlights, violet shadows, low saturation outside the light, slightly lifted blacks, fine film grain. Real Mexican architecture; people only as hands or from behind.

## Palette (named hex, stated in every prompt)
Aubergine #160C24 · Plum Glass #25153C · Pearl #F4EFF8 · Lilac Mist #BCA9D5 · Amethyst #AB81F2 · Lantern Gold #F4B64C (the only warm light) · Bone #F4ECE0 (card/linen only).

## Assets (10 images)
| # | File | Content | Ratio / target | Why |
|---|---|---|---|---|
| 1 | `banner/hero-courtyard-dusk` **ANCHOR (generated alone first)** | The approved board direction at full quality, as in contact-sheet v2 panel 1: deep Mexican colonial courtyard, grand arch framing a second arch and corridor, hanging lantern, plants and vines, gold light spilling on cobbles; arch in the right third, clean dark space on the left for the headline | 16:9, 2752px, WebP | Landing hero still + first frame of the scroll video |
| 2 | `heroes/casita-costa-noche` | Whitewashed Cycladic-style beach house with a rounded ARCH entrance (founder request, contact-sheet v2), Mexican Caribbean charm: palms, pale sand, glimpse of sea, violet dusk | 16:9 | Property variety (beach) |
| 3 | `heroes/loft-cdmx-noche` | Mexico City building street door at night, one lit doorway | 16:9 | Property variety (city) |
| 4 | `action/llave-en-puerta` | Hand turning a brass key, gold light along the door gap | 16:9 | The "hand-off" (gold) moment |
| 5 | `action/telefono-boca-abajo` | A hand setting a phone face-down beside a lit lamp, evening | 16:9 | "Regálate tiempo": time back |
| 6 | `detail/llave-laton-lino` | Brass key on bone linen, warm side light | 16:9 | Quality story |
| 7 | `detail/farol-pared` | Wrought-iron lantern on plaster, violet shadow | 16:9 | Quality story |
| 8 | `lifestyle/huesped-llega` | Guest seen from behind with a suitcase approaching the lit door | 16:9 | Guest side |
| 9 | `lifestyle/anfitrion-terraza` | Host's hands on a terrace at dusk, cup, phone face-down, no face | 16:9 | Host side, calm |
| 10 | `extras/tarjeta-puerta-oro` | The bone door-hanger with the embossed aubergine-ink arch and gold-foil door (the one the founder loved), regenerated at full resolution from logo references | 16:9 | Print / social touchpoint |

## Order and gates
1. Generate #1 alone. Founder approves the anchor (or I regenerate it once).
2. Generate #2-#10 with the anchor image + style DNA attached to each prompt (one asset per prompt).
3. QA the set (consistency, palette adherence by sampling dominant colours, anti-generic). Regenerate failures once.
4. Write `manifest.md` (file, model, prompt, cost) and `embed-guide.md`.

## Cost
10 images × $0.134 = **$1.34** + references ≈ $0.01 → **≈ $1.35 expected**. Regeneration allowance: up to 3 failed assets once → **hard cap ≈ $1.75**. Billed to the GCP credit. (4K is not needed: 2K already covers a full-width 1920px hero at ~1.4x.)
