---
version: alpha
name: Mayordommo-lit-doorway
description: "A calm, night-shift hospitality system for an AI guest concierge: deep aubergine canvas (#160C24) lifted by plum glass cards, pearl text, and a single warm light, Lantern Gold (#F4B64C), that only ever means 'a person is needed' or 'someone is home'. Amethyst purple is Alfred's presence (glow, bubbles, focus). Pages open as a dark night hero and hand over to warm bone (#F4ECE0) sections; the light theme keeps the same logic with ink hairlines instead of glow. Display type is Cormorant Garamond Bold (700), UI and body are Manrope. One red, Óxido, is reserved for urgent or failed states. Photography is cinematic Mexican architecture at dusk with one lit doorway."

colors:
  # Dark theme (default, night hero)
  canvas: "#160C24"
  surface: "#25153C"
  ink: "#F4EFF8"
  ink-muted: "#BCA9D5"
  hand: "#F4B64C"
  on-hand: "#160C24"
  hand-text: "#F4B64C"
  brand: "#AB81F2"
  brand-text: "#BA96F6"
  status: "#90CEA8"
  danger: "#DB6D63"
  on-danger: "#160C24"
  # Light theme (bone sections)
  light-canvas: "#F4ECE0"
  light-surface: "#FCF8F1"
  light-ink: "#1B102C"
  light-ink-muted: "#5E4D75"
  light-on-hand: "#1B102C"
  light-brand: "#6235AF"
  light-brand-text: "#6235AF"
  light-status: "#2E6A4C"
  light-danger: "#A6382E"
  light-on-danger: "#FCF8F1"
  light-hand-text: "#87570A"

# Typography: the pairing (Cormorant Garamond 700 + Manrope) is a locked decision.
# The size scale below is a working default, not a brand decision; tune it in the landing build.
typography:
  display-xl:
    fontFamily: Cormorant Garamond
    fontSize: 88px
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: -1.5px
  display-lg:
    fontFamily: Cormorant Garamond
    fontSize: 60px
    fontWeight: 700
    lineHeight: 1.06
    letterSpacing: -1.0px
  display-md:
    fontFamily: Cormorant Garamond
    fontSize: 42px
    fontWeight: 700
    lineHeight: 1.10
    letterSpacing: -0.5px
  headline:
    fontFamily: Cormorant Garamond
    fontSize: 30px
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: 0
  wordmark:
    fontFamily: Cormorant Garamond
    fontSize: 56px
    fontWeight: 700
    lineHeight: 1.0
    letterSpacing: 0.01em
  card-title:
    fontFamily: Manrope
    fontSize: 19px
    fontWeight: 600
    lineHeight: 1.30
    letterSpacing: 0
  body-lg:
    fontFamily: Manrope
    fontSize: 18px
    fontWeight: 500
    lineHeight: 1.55
    letterSpacing: 0
  body:
    fontFamily: Manrope
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.55
    letterSpacing: 0
  body-sm:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.50
    letterSpacing: 0
  caption:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: 600
    lineHeight: 1.40
    letterSpacing: 0.02em
  button:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: 700
    lineHeight: 1.20
    letterSpacing: 0
  eyebrow:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: 600
    lineHeight: 1.30
    letterSpacing: 0.08em

# Radii are taken from the approved reference sheet (brand-preview.html).
rounded:
  sm: 10px
  md: 12px
  lg: 14px
  xl: 16px
  pill: 999px

spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  section: 96px

components:
  button-primary:
    backgroundColor: "{colors.hand}"
    textColor: "{colors.on-hand}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: 10px 16px
  button-primary-light:
    backgroundColor: "{colors.hand}"
    textColor: "{colors.light-on-hand}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: 10px 16px
  button-urgent:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.on-danger}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: 10px 16px
  button-urgent-light:
    backgroundColor: "{colors.light-danger}"
    textColor: "{colors.light-on-danger}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: 10px 16px
  chip-hand-off:
    backgroundColor: "{colors.hand}"
    textColor: "{colors.on-hand}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: 6px 10px
  chip-status:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.status}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: 6px 10px
  chip-urgent:
    backgroundColor: "{colors.danger}"
    textColor: "{colors.on-danger}"
    typography: "{typography.caption}"
    rounded: "{rounded.pill}"
    padding: 6px 10px
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 20px
  card-light:
    backgroundColor: "{colors.light-surface}"
    textColor: "{colors.light-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.lg}"
    padding: 20px
  window:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.xl}"
    padding: 24px
  window-light:
    backgroundColor: "{colors.light-canvas}"
    textColor: "{colors.light-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.xl}"
    padding: 24px
  bubble-alfred:
    backgroundColor: "{colors.brand}"
    textColor: "{colors.on-hand}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.lg}"
    padding: 10px 14px
  bubble-guest:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.lg}"
    padding: 10px 14px
  text-input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 10px 14px
  top-nav:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.sm}"
    height: 64px
---

## Overview

Mayordommo is the public brand of an AI concierge that answers vacation-rental guests on WhatsApp, Telegram or the web and calls the host in only when it matters. The in-product butler is **Alfred** ("he"). The visual world is a lamp left on at night: a deep aubergine canvas, one warm light, and calm, plain-spoken type. The core metaphor is the **threshold**: someone is home and the light is on. The logo is a lit doorway (an arch with a gold door floating over its own reflection), never a letter or monogram.

Pages follow one structure: a **night hero** (`{colors.canvas}`) with the lit-doorway photography and a clean left-hand space for the headline, then **bone sections** (`{colors.light-canvas}`) for calm explanation, with the same logic and no glow. Every measured competitor site uses a light canvas; the dark-first hero is a deliberate code-break (IDENTITY.md §9).

**Key characteristics**
- One warm light only: Lantern Gold `{colors.hand}`. It means "a person is needed", the primary action, and the doorway light. Never decoration.
- Purple is Alfred's presence: glow around cards and pop-ups (dark only), his chat bubbles, status dots, focus, and purple links.
- One red, Óxido (`{colors.danger}` / `{colors.light-danger}`), only for urgent or failed states, always with an icon and a label.
- Display type is Cormorant Garamond Bold (700); UI and body type is Manrope. The wordmark is lowercase `mayordommo` in Cormorant Garamond 700.
- Spanish first (Mexico), written natively in tú; the product words are plain ("Train now", "autopilot", "step in"), never ingest, scrape or merge.

## Colors

Source of truth: `palette.md` and `tokens.json` (Violet Hour 75% / Dusk Plum 25%). Never change a hex without the founder's approval.

### Dark theme (default)
- **Aubergine** `{colors.canvas}` page and window background. **Plum Glass** `{colors.surface}` cards, panels, inputs.
- **Pearl** `{colors.ink}` text and the logo arch. **Lilac Mist** `{colors.ink-muted}` secondary text.
- **Lantern Gold** `{colors.hand}`: hand-off, primary button fill, doorway light; text on it is `{colors.on-hand}`. Gold as text (`{colors.hand-text}`) is allowed in the dark theme only.
- **Amethyst** `{colors.brand}` glows, bubbles, dots, focus; **Lilac** `{colors.brand-text}` purple text and links.
- **Celadon** `{colors.status}` autopilot-OK dot and text.
- **Óxido** `{colors.danger}` urgent or failed; text on it `{colors.on-danger}`.

### Light theme (bone sections)
- **Bone** `{colors.light-canvas}` and **Bone Light** `{colors.light-surface}`; **Aubergine Ink** `{colors.light-ink}` text and logo arch; **Dusk Violet** `{colors.light-ink-muted}` secondary text.
- **Deep Amethyst** `{colors.light-brand}` brand, links and focus; **Deep Celadon** `{colors.light-status}` status; **Óxido** `{colors.light-danger}` urgent or failed with `{colors.light-on-danger}` on fills.
- Gold stays `{colors.hand}` with `{colors.light-on-hand}` text, as a **chip or button fill only**. No brass or ochre text (`{colors.light-hand-text}` exists only as a rare fallback), no lilac wash on surfaces.

All text pairs meet WCAG AA (lowest 5.1:1, see `palette.md`).

## Typography

Cormorant Garamond 700 for the wordmark, tagline and display headlines; Manrope for everything the user reads or taps. Text is real type in the design layer, never baked into images (so it can be edited, translated and made accessible). The sizes in the front matter are working defaults to tune in the landing build; the pairing and weights are decisions.

| Token | Size | Weight | Use |
|---|---|---|---|
| `{typography.display-xl}` | 88px | 700 | Hero headline ("Regálate tiempo." is the working line) |
| `{typography.display-lg}` | 60px | 700 | Section openers |
| `{typography.display-md}` | 42px | 700 | Sub-sections |
| `{typography.headline}` | 30px | 700 | Card and banner headings |
| `{typography.wordmark}` | 56px | 700 | The wordmark lockup |
| `{typography.body-lg}` / `{typography.body}` | 18 / 16px | 500 | Body copy |
| `{typography.button}` / `{typography.caption}` / `{typography.eyebrow}` | 14 / 12 / 12px | 700 / 600 / 600 | Buttons, chips, eyebrows |

## Layout

Spacing steps 4 / 8 / 12 / 16 / 24 / 32 / 48 and a 96px section rhythm. Pages are a night hero then bone sections; content max-width ~1200px; hero copy occupies the clean left two thirds, the lit doorway sits right of centre. Mobile: single column, 16px side gutter, hero image uses `object-position:70% 50%`.

## Shape and elevation

Radii: 10px controls, 12px inputs, 14px cards, 16px windows, pill chips. **Elevation is light, not shadow.**
- **Dark theme:** cards and pop-up windows get a soft purple glow: `0 0 0 1px` Amethyst at ~33%, plus `0 8px 36px -8px` Amethyst at ~42%. An attention card (needs a person) gets the same recipe in Lantern Gold; an urgent card in Óxido.
- **Light theme: no glow** (it looked dirty on bone). Windows and pop-ups get a 1px Aubergine Ink hairline (~22%); inner cards get a 1px Deep Amethyst outline (~32%). Urgent cards: 1px Óxido hairline.

## Components

- **Primary button:** Lantern Gold fill, ink text, `{rounded.sm}`. One per view. **Urgent button:** Óxido fill, `{colors.on-danger}` text.
- **Chips:** hand-off (gold fill, "Te necesitan"), status (celadon outline, dot, "Autopiloto"), urgent (Óxido fill). Placeholder Spanish labels, copy to be written natively.
- **Cards and windows:** Plum Glass card on Aubergine with the purple glow (dark); Bone Light card with the faint purple outline (light).
- **Chat:** guest messages on Plum Glass; Alfred's on Amethyst; a gold "step in" pill when a person is needed.
- **Logo and nav:** full mark at 40px and above (`logo/mayordommo-mark-*.svg`), flat mark below that and as the favicon; leave clear space under the logo so the reflection ends before the letters.

## Imagery and motion

Photography: cinematic night shots of Mexican architecture lit by one pale-golden practical light, aubergine-violet shadows, matte materials, fine grain; people only as hands or from behind; no text, logos or faces. Assets and prompts: `manifest.md`, `embed-guide.md`, `web/*.webp`. The hero still is also the first frame of the scroll-driven video (one slow camera move toward and through the lit doorway; poster and reduced-motion fallback = the still).

## Do and don't

- Do keep gold meaning "a person is needed" (or the doorway light); do pair Óxido with an icon and label; do keep the purple glow dark-only; do write plain Spanish.
- Don't use a letter or M monogram, a purple arch, ochre or brass in the light theme, a lilac wash on bone, teal/coral/blue SaaS styling, robot or sparkle icons, "24/7" or "AI-powered" copy, or any hex outside `palette.md`.
