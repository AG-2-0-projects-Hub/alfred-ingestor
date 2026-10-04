# Mayordommo palette — LOCKED 2026-10-02

**Source:** the Violet Hour ↔ Dusk Plum blend at **25% toward Dusk Plum** (75% Violet Hour), chosen by the founder after five rounds of artifact previews. Machine-readable copy: `tokens.json`. Reference page: `brand-preview.html`.

**Never change a hex here without the founder's approval.** Every generated asset stays inside this palette (BRAND_IDENTITY_PROTOCOL Hard Rule 2).

### Dark theme

| Token | Name | Hex | Role |
|---|---|---|---|
| `canvas` | Aubergine | `#160C24` | Page / window background |
| `surface` | Plum Glass | `#25153C` | Cards, chat panels, inputs |
| `text` | Pearl | `#F4EFF8` | Primary text and the logo arch |
| `muted` | Lilac Mist | `#BCA9D5` | Secondary text |
| `hand` | Lantern Gold | `#F4B64C` | Hand-off, primary button fill, door light. The ONLY gold. Means: a person is needed |
| `onhand` | Aubergine (text on gold) | `#160C24` | Text on gold fills |
| `handtx` | Lantern Gold (as text) | `#F4B64C` | Gold used as text (dark theme only; on light use a gold chip with dark text instead) |
| `brand` | Amethyst | `#AB81F2` | Alfred / brand presence: glows, bubbles, focus, dots |
| `brandtx` | Lilac (purple text) | `#BA96F6` | Purple used as text and links |
| `status` | Celadon | `#90CEA8` | Autopilot OK dot and text |
| `danger` | Óxido | `#DB6D63` | Emergency / failed states only (added 2026-10-03, founder pick C0) |
| `ondanger` | Aubergine (text on Óxido) | `#160C24` | Text on Óxido fills |

Contrast (WCAG): text/canvas 16.7 · text/surface 14.8 · muted/canvas 8.8 · muted/surface 7.8 · brandtx/canvas 7.9 · brandtx/surface 7.0 · status/canvas 10.4 · status/surface 9.3 · onhand/hand 10.5 · handtx/canvas 10.5 · brand/canvas 6.4 · danger/canvas 5.7 · danger/surface 5.1 · ondanger/danger 5.7

### Light theme

| Token | Name | Hex | Role |
|---|---|---|---|
| `canvas` | Bone | `#F4ECE0` | Page / window background |
| `surface` | Bone Light | `#FCF8F1` | Cards, chat panels, inputs |
| `text` | Aubergine Ink | `#1B102C` | Primary text and the logo arch |
| `muted` | Dusk Violet | `#5E4D75` | Secondary text |
| `hand` | Lantern Gold | `#F4B64C` | Hand-off, primary button fill, door light. The ONLY gold. Means: a person is needed |
| `onhand` | Aubergine Ink (text on gold) | `#1B102C` | Text on gold fills |
| `handtx` | Brass (rare, text only) | `#87570A` | Gold used as text (dark theme only; on light use a gold chip with dark text instead) |
| `brand` | Deep Amethyst | `#6235AF` | Alfred / brand presence: glows, bubbles, focus, dots |
| `brandtx` | Deep Amethyst (purple text) | `#6235AF` | Purple used as text and links |
| `status` | Deep Celadon | `#2E6A4C` | Autopilot OK dot and text |
| `danger` | Óxido (deep) | `#A6382E` | Emergency / failed states only (added 2026-10-03, founder pick C0) |
| `ondanger` | Bone Light (text on Óxido) | `#FCF8F1` | Text on Óxido fills |

Contrast (WCAG): text/canvas 15.5 · text/surface 17.1 · muted/canvas 6.4 · muted/surface 7.1 · brandtx/canvas 6.8 · brandtx/surface 7.5 · status/canvas 5.5 · status/surface 6.0 · onhand/hand 10.1 · danger/canvas 5.6 · danger/surface 6.1 · ondanger/danger 6.1

## Usage rules (decided)

1. **Gold means a person is needed.** Lantern Gold is the only saturated warm hue. It is used for hand-off states, the primary button, and the doorway light in the logo. Never for decoration.
2. **Purple is Alfred's presence.** Amethyst is used for glows around cards and pop-up windows, Alfred's chat bubbles, status dots, links (as purple text) and focus. Cards and windows get a soft purple glow in the DARK theme only; in the LIGHT theme there is NO glow (it looked dirty on bone): windows and pop-ups get a 1px Aubergine Ink hairline (~22%) and inner cards a 1px faint purple outline (~32% Deep Amethyst). The gold glow is reserved for the "needs your attention" state.
3. **Light theme has no brass or ochre.** Gold on bone fails contrast as text or thin lines, so on light use a solid gold chip with dark text, and purple for links. The doorway stays bright gold because the dark arch carries its edge.
4. **The logo arch is the text colour** (Pearl on dark, Aubergine Ink on light). It is NOT purple. The doorway light is Lantern Gold in both themes.
5. **Light surfaces:** bone canvas with a lighter bone for cards. No lilac wash on surfaces (it looked muddy).
6. **Dark theme:** Aubergine canvas, Plum Glass surfaces, Pearl text. Muted text is Lilac Mist.
7. Spanish-first copy; no text baked into generated images.
8. **Óxido (red) means urgent or failed, nothing else** (added 2026-10-03). Never decoration, never branding. Always paired with an icon and a label, never colour alone. Gold stays "a person is needed" (not urgent); Óxido is "urgent / something failed" (emergency, message not sent, destructive confirm). Dark theme: urgent card gets a 1px Óxido hairline plus a soft Óxido glow (like the gold attention glow); light theme: 1px Óxido hairline, no glow. Solid fills use `ondanger` text. Picked over rose/scarlet/garnet (too watermelon) and terracotta, adobe, siena variants; C3 Cálido `#D67060`/`#A13C2D` was the runner-up (ΔE ≈ 4, barely different).
