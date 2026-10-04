---
name: vista-design
version: alpha
description: >
  An editorial wilderness-travel landing page on a warm bone-paper surface
  (#F4EFE6) with deep pine ink (#192820). Its voltage is a clay-orange accent
  (#C44C27) paired with a muted forest green (#3E6F60). The signature move is a
  900-weight italic Fraunces display face with variable SOFT/optical-size axes,
  set against monospace JetBrains Mono italic eyebrows and a light Inter Tight
  body. Geometry is deliberately edge-to-edge and squared — zero border radius
  — with asymmetric hero placement, a pinned split-screen destination swap, an
  SVG route that draws on scroll, and cursor-tracked floating previews.
colors:
  # Surface
  bg-primary: '#F4EFE6'     # warm bone-paper page surface (body, light sections)
  bg-secondary: '#E5EBE0'   # pale sage alt surface (declared, sparingly used)
  surface-dark: '#192820'   # deep pine; method section, footer, scrolled nav
  # Brand / Accent
  accent-1: '#C44C27'       # clay orange — primary voltage; CTAs, links, active dots, SVG path
  accent-1-hover: '#a33a1c' # darker clay on button hover
  accent-2: '#3E6F60'       # muted forest green — eyebrows, visual tints, preview bg
  # Text
  text-primary: '#192820'   # pine ink — headings/body on light surface
  text-muted: '#7B9082'     # sage gray — body copy, secondary, progress dots
  text-on-dark: '#F4EFE6'   # bone text on dark surfaces
  # Hairlines
  hairline-dark: 'rgba(25,40,32,0.12)'    # dispatch list rules on light
  hairline-light: 'rgba(244,239,230,0.2)' # newsletter input border on dark
  # Gradient
  hero-gradient: 'linear-gradient(135deg, #192820 0%, #3E6F60 100%)' # hero fallback behind video
typography:
  display:
    fontFamily: "'Fraunces', serif"
    fontSize: clamp(30px, 4.2vw, 56px)
    fontWeight: 900
    lineHeight: 1.08
    letterSpacing: -0.03em
  display-large:
    fontFamily: "'Fraunces', serif"
    fontSize: clamp(48px, 5.5vw, 72px)
    fontWeight: 900
    lineHeight: 1.05
  eyebrow:
    fontFamily: "'JetBrains Mono', monospace"
    fontSize: 11px
    fontWeight: 400
    letterSpacing: 0.14em
    textTransform: uppercase
  body:
    fontFamily: "'Inter Tight', sans-serif"
    fontSize: 16px
    fontWeight: 300
    lineHeight: 1.8
  label:
    fontFamily: "'Inter Tight', sans-serif"
    fontSize: 12px
    fontWeight: 500
    letterSpacing: 0.12em
    textTransform: uppercase
rounded:
  none: 0px      # everything is squared; circular only for tiny dots
  full: 9999px   # 5px progress dots (border-radius:50%)
spacing:          # base unit 4px; layout gutters use 8vw
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 60px
  3xl: 120px
components:
  nav:
    backgroundColor: 'transparent'
    scrolledBackground: 'rgba(25,40,32,0.93)'
    textColor: '{colors.text-on-dark}'
    padding: '28px 8vw'
    note: 'fixed; on scroll adds blur(12px) backdrop + dark fill, shrinks to 18px pad'
  nav-cta:
    textColor: '{colors.text-on-dark}'
    border: '1px solid rgba(244,239,230,0.35)'
    typography: '{typography.eyebrow}'
    rounded: '{rounded.none}'
    padding: '10px 22px'
  hero-cta:
    backgroundColor: '{colors.accent-1}'
    textColor: '{colors.text-on-dark}'
    typography: '{typography.label}'
    rounded: '{rounded.none}'
    padding: '15px 30px'
  dest-panel-link:
    textColor: '{colors.accent-1}'
    border: 'bottom 1px solid {colors.accent-1}'
    typography: '{typography.label}'
    padding: '0 0 3px'
  dispatch-item:
    borderTop: '1px solid {colors.hairline-dark}'
    titleTypography: '{typography.display}'
    hoverColor: '{colors.accent-1}'
    padding: '36px 0'
  newsletter-input:
    backgroundColor: 'transparent'
    border: '1px solid {colors.hairline-light}'
    textColor: '{colors.text-on-dark}'
    typography: '{typography.body}'
    rounded: '{rounded.none}'
    padding: '12px 16px'
  newsletter-btn:
    backgroundColor: '{colors.accent-1}'
    textColor: '{colors.text-on-dark}'
    rounded: '{rounded.none}'
    padding: '12px 22px'
motion:
  ease: 'cubic-bezier(0.16, 1, 0.3, 1) — the house easing on nearly every transition'
  hero-line-rise: 'masked headline lines translateY(110%)→0 over 800ms, staggered 120ms per line'
  hero-stagger: 'subhead 720ms delay, CTA 1050ms, meta 1400ms fade/slide-in on load'
  pinned-swap: 'destination text panels cross-fade + 18px rise as scroll progress crosses 0.25/0.50/0.75 thresholds'
  svg-draw: 'method route path stroke-dashoffset drawn from full length to 0 tied to scroll progress'
  field-heading-windup: 'letter-spacing 0.32em→0 and opacity 0.4→1 over 950ms on enter'
  footer-wordmark: 'letter-spacing 0.6em→0.02em and opacity over 1200ms on enter'
  cursor-preview: 'floating image clip-path inset reveal + scale, lerp-tracked to cursor at 0.12'
  hero-parallax: 'hero video scales 1→1.06 over first 0.6 viewport of scroll'
icons:
  library: inline text glyphs (no icon font)
  style: arrow characters (→) used as CTA/affordance marks
  color: '{colors.text-on-dark}'
---

# Horizon

`vista-design · alpha`

> Design spec — version alpha. Source: static HTML (`index.html`); tokens read
> from inline styles + class rules. Fictional/sample product; described factually.

## Overview
Horizon is an editorial landing page for a premium wilderness-travel brand,
built on a warm bone-paper surface `#F4EFE6` with deep pine ink `#192820` for
type. The voltage is a clay-orange `#C44C27` used sparingly for CTAs, links,
the SVG route, and active progress dots, supported by a muted forest green
`#3E6F60` for eyebrows and image tints. The type story is the centerpiece: a
900-weight *italic* Fraunces display (with variable `SOFT` and `opsz` axes) sets
every headline, JetBrains Mono italic carries the monospace eyebrows and
geographic meta-rows, and a light (300) Inter Tight handles body copy. Geometry
is squared throughout — there is no border radius anywhere except 5px circular
progress dots — and the page leans on full-bleed compositions: an asymmetric
hero (headline lower-left, CTA upper-right), a pinned split-screen destination
swap, an SVG route that draws as you scroll, and cursor-tracked floating preview
images over the dispatch list.

## Colors
**Surface.** The page rests on `--bg-primary: #F4EFE6`, a warm bone paper, used
for the body and light sections. `--bg-secondary: #E5EBE0` (pale sage) is
declared as an alternate surface. `--surface-dark: #192820` (deep pine) backs
the Method section, the footer, and the scrolled nav fill.

**Brand / Accent.** `--accent-1: #C44C27` (clay orange) is the single voltage:
hero CTA, newsletter button, dest/dispatch links, active progress dot, the SVG
route stroke, and the footer top border. It darkens to `#a33a1c` on button
hover. `--accent-2: #3E6F60` (muted forest green) appears in eyebrows, the
destination image tint `rgba(62,111,96,0.18)`, and as the placeholder background
behind preview images.

**Text.** `--text-primary: #192820` for headings and body on light surfaces;
`--text-muted: #7B9082` (sage gray) for secondary body and inactive dots; on
dark surfaces text is `#F4EFE6`, often at reduced opacity (0.78 / 0.65 / 0.55 /
0.28).

**Hairlines.** Light-surface rules use `rgba(25,40,32,0.12)` (dispatch list
borders); dark-surface inputs use `rgba(244,239,230,0.2)`.

**Gradient.** The hero shows `linear-gradient(135deg, #192820 0%, #3E6F60 100%)`
as a fallback behind the autoplaying video, plus a subtle two-band top/bottom
overlay in `rgba(25,40,32, …)` rather than a full dark wash.

## Typography
Three families load from Google Fonts: **Fraunces** (display serif, used at
weight 900, italic, with `font-variation-settings: 'SOFT' 100, 'opsz' 144`),
**Inter Tight** (body sans, weights 300/400/500), and **JetBrains Mono** (italic
400, eyebrows and numerals). All are open-source and load via a single Google
Fonts `@import`/`<link>`.

| Token | Size | Weight | Line-height | Tracking | Usage |
|---|---|---|---|---|---|
| display | clamp(30px,4.2vw,56px) | 900 italic | 1.08 | -0.03em | hero & panel headings |
| display-large | clamp(48px,5.5vw,72px) | 900 italic | 1.05 | -0.02em/0.32em | field heading, dispatch titles |
| eyebrow | 11px | 400 italic | — | 0.14em | mono eyebrows, meta-rows |
| body | 16px | 300 | 1.8 | — | panel/method body copy |
| label | 12px | 500 | — | 0.12em | CTA & link labels (uppercase) |
| step-number | 72px | 400 italic | 1 | -0.04em | method step numerals (mono, 14% opacity) |
| wordmark | clamp(56px,11vw,160px) | 900 | — | 0.6em→0.02em | footer "HORIZON" ghost wordmark |

## Layout
Base spacing unit is 4px; horizontal gutters are consistently `8vw`. The page is
a single vertical scroll of full-bleed sections: a 100vh hero with asymmetric
absolute placement (headline at `bottom:28vh/left:8vw`, CTA at
`top:22vh/right:8vw`, meta-row bottom-left); a 300vh pinned destinations section
whose sticky `1fr 1fr` grid locks a left visual while right-side text panels
swap; a centered Method section on dark pine with a 3-column step grid under an
SVG route; a dispatch list with full-width rows separated by hairlines; and a
dark footer with a `2fr 1fr 1fr 2fr` grid beneath a giant ghost wordmark. No
fixed max-width container — content spans the viewport with vw gutters.
Whitespace is generous and editorial.

## Elevation & Depth
The system is essentially flat — there are no drop shadows. Depth comes from
layering instead: the scrolled nav uses `backdrop-filter: blur(12px)` over a
93%-opaque pine fill (the only glass), section color blocks (bone vs. pine vs.
green) establish planes, image tints and the two-band hero overlay add
atmosphere, and the footer's near-transparent ghost wordmark
(`rgba(244,239,230,0.08)`) recedes behind the grid. The floating cursor preview
sits at `z-index:50`, fixed, with no shadow — its reveal is a clip-path wipe.

## Shapes
Hard-edged by intent: virtually every element has `border-radius: 0`. Buttons,
inputs, image frames, and panels are all squared rectangles. The only curve in
the system is the 5px progress dot (`border-radius:50%`), which scales 1.4× when
active. This squared geometry is the structural signature.

## Components
- **nav** — fixed, transparent; on scroll gains `rgba(25,40,32,0.93)` +
  `blur(12px)` backdrop, padding shrinks `28px→18px`. Logo in Fraunces italic.
- **nav-cta** ("Begin") — transparent, `1px solid rgba(244,239,230,0.35)`,
  mono italic 11px uppercase, `10px 22px`, square; hover borders clay + 15% fill.
- **hero-cta** ("Explore Journeys →") — solid `#C44C27`, bone text, label type,
  `15px 30px`, square; hover `#a33a1c`.
- **dest-panel-link** ("Explore Patagonia →") — clay text with a clay 1px
  bottom border, uppercase label; hover fades to 0.65.
- **dispatch-item** — full-width row, `1px` top hairline, Fraunces italic title
  up to 52px; hover turns title clay and reveals an underline rule.
- **newsletter-input** — transparent, `1px` bone-20% border (no right border),
  bone text, `12px 16px`, square; focus border goes clay-60%.
- **newsletter-btn** ("→") — solid clay, bone glyph, `12px 22px`, square.
- **progress dots** — 5px circles, muted by default, clay + 1.4× scale active.

## Motion
A single house easing `cubic-bezier(0.16, 1, 0.3, 1)` governs nearly every
transition. On load the hero plays a masked line-rise (headline lines
`translateY(110%)→0`, 800ms, staggered 120ms), then the subhead (720ms delay),
CTA (1050ms), and meta-row (1400ms) fade in. Scroll drives the rest via a RAF
loop: the hero video scales `1→1.06` over the first 0.6vh; the pinned
destinations cross-fade panels at progress thresholds 0.25/0.50/0.75; the Method
SVG route draws via `stroke-dashoffset` tied to scroll, with step text fading in
at 0.15/0.48/0.78. IntersectionObservers fire one-shot wind-ups: the field
heading collapses letter-spacing `0.32em→0`, the footer wordmark `0.6em→0.02em`,
and dispatch items stagger-rise. On desktop, a floating preview image lerp-tracks
the cursor (0.12) and reveals via a clip-path inset wipe.

## Iconography
No icon font is used. Affordances are plain arrow glyphs (`→`) appended to CTA
and link labels and as the newsletter submit button. Color follows context —
bone on dark, clay on light links.

## Do's and Don'ts
- **Do** keep Fraunces at 900 italic with the SOFT/opsz variation axes — it is
  the brand's voice.
- **Do** reserve clay `#C44C27` as a rare voltage (CTAs, links, the route,
  active states) against the bone-and-pine base.
- **Do** keep everything squared; preserve the asymmetric hero diagonal.
- **Don't** introduce border radius (beyond the dots), drop shadows, or a heavy
  dark hero wash — the overlay is intentionally a light two-band gradient.
- **Don't** set body copy heavier than 300, or let the mono eyebrows lose their
  italic + wide tracking.

## Known Gaps
- `--bg-secondary: #E5EBE0` is declared in `:root` but not visibly applied in
  the markup; included for completeness.
- The hero video/imagery are remote CDN assets; their visual content is not
  part of the token system.
- Spacing scale (`60px`, `120px`) is inferred from section paddings; the
  underlying unit is 4px but layout gutters use viewport units (`8vw`).