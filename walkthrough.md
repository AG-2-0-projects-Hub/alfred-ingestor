# Post-training walkthrough — content map

Extracted 2026-09-11 before rebuilding Parts B and C from scratch (the tip
panels in these parts render with an unexplained rendering bug — huge
red/bold/underlined text — that survived every isolation test: different
machines, incognito, blur disabled, repaint boundary. Root cause never found;
decision was to rebuild rather than keep chasing it). This doc is the copy +
structure reference for that rebuild.

**Robot marker:** every step header is prefixed with the 🤖 emoji, exactly as
shown below — that's a literal `Text('🤖', ...)` next to the step-counter
label in the original code, not a copy-paste artifact.

---

## The highlight/glow effect (plain description, being KEPT)

Every walkthrough step has two visual pieces working together:

1. **The text bubble** — a small card with a robot emoji, "step X of Y",
   a bold header line, a paragraph of body text, and Back/Next buttons. This
   is the part with the rendering bug (giant red/bold/underlined text) and
   the part being deleted.
2. **The glow outline** — a purple rounded-rectangle border with a soft
   purple drop-shadow, drawn directly around whatever real on-screen element
   that step is talking about (a button, a text field, a whole panel). This
   fades in/out over about a quarter of a second whenever the walkthrough
   moves to a step that targets it. This is the part that looks good and is
   being kept.

Screenshots from this session showing the glow on its own (real screenshots,
described here since they can't be saved as files from the chat — see
`walkthrough_reference/` for anything dropped in manually):

- Purple outline around the whole property name/status bar at the top of the
  Host Chat window ("Dos rios / Test walkthrough").
- Purple outline around the box of generated guest links (web/WhatsApp/
  Telegram + the copy icons) after clicking Generate Link.
- Purple outline around the small "Automated Learning" chip.
- Purple outline around the "Add New Knowledge" text input box.
- Purple outline around the Autopilot/Intervene mode switcher.

**Is the glow related to the underline bug?** Worth checking, but unlikely on
inspection: the glow is a plain animated colored border + shadow around a
box — it doesn't touch any text styling, and it renders fine on its own in
every screenshot above (no underline ever appears on the glow itself or
right next to it when the *text bubble* isn't also present). The two most
likely-looking rendering bugs (blur, and being nested deep in a dialog) were
both ruled out by direct testing this session without touching the glow code
at all. Flagging this only so whoever rebuilds it double-checks rather than
assuming it's cleared for certain.

---

## Part A — KEPT AS-IS, working correctly, not being touched

- **Dashboard Step 0 tip** (`frontend/lib/widgets/property_card.dart`,
  `_Step0Tip` + `CompositedTransformFollower`/`Overlay.insert`). Shows once,
  right on the property card, no dialog/drawer involved.
- **Add Property walkthrough** (`frontend/lib/widgets/add_property_walkthrough_panel.dart`,
  3 steps: Paste listing URL → Upload Files → Train Now). Docked panel beside
  the Add Property form.

Both of these are the reference pattern for how the rebuild should probably
work (or at least: proof that this general approach — docked/overlay panel +
glow highlight — can render cleanly).

---

## Part B — Settings drawer walkthrough (TO BE REMOVED)

Source: `frontend/lib/widgets/property_detail_drawer.dart`
State: `_wtStep` (0–4), `_wtStepInfo(step)`, panel: `_buildWalkthroughPanel()`
Fires: first time a property's Settings drawer opens after training completes
(status in `Trained`/`Active`/`Resolved`/`Merged`), once per property,
tracked via `WalkthroughPrefs.isPostTrainingSeen(propertyId)`.
Docked as a 300px-wide panel to the left of the drawer (desktop only, ≥1000px
viewport — below that, only the glow-highlight shows, panel is dropped
entirely, which is itself a separate known bug worth fixing in the rebuild).

| Step | Highlights (GlobalKey) | Header | Body |
|---|---|---|---|
| 1 of 5 | `_wtDrawerKey` (whole drawer) | I've learned {property name} — here's what's next | This is where you'll come back anytime: add more detail, see what I picked up on my own, or ask me something to check my work. |
| 2 of 5 | `_wtManageKey` (Manage files button) | Add or swap files anytime | Tap Manage to upload more — a new house manual, an updated WiFi photo, anything. I'll fold it in without starting over. |
| 3 of 5 | `_wtAddKnowledgeKey` ("Add New Knowledge" field) | Tell me something directly | Type it, or record a voice note — parking rules, a fix for the shower, whatever's easiest. I'll add it to what I already know. |
| 4 of 5 | `_wtLearningKey` (learned-facts review area) | I flag what I learn on my own | Every real guest conversation teaches me something — I'll surface it here for your OK before it sticks. |
| 5 of 5 | `_wtChatKey` (Host Chat test button) | Double-check me anytime | Ask me something here, the same way a guest would. It's the fastest way to see exactly what I'd tell them — before they ever ask. |

**Keep:** the `_wtHighlight()` glow wrapper (purple 2px border + soft shadow,
`AnimatedContainer`, 250ms) around each of the 5 target elements above — this
is the part that "looks pretty good," per feedback, and isn't implicated in
the rendering bug.

**Remove:** `_buildWalkthroughPanel()` (the floating/docked `GlassPanel` tip
box itself), `_wtStep`/`_wtStepInfo`/`_wtGoToStep`/`_wtNext`/`_wtBack`/`_wtFinish`
state machine, the `Row`-docking logic in the build method that inserts the
panel beside the drawer, and the "Show walkthrough again" toggle's dependency
on this state (will need to point at whatever replaces it).

---

## Part C — Guest Link + Host Chat walkthrough (TO BE REMOVED)

One continuous 9-step sequence spanning two files, sharing a single
"X of 9" counter. Fires on the first-ever guest link generated across *any*
property (global flag via `WalkthroughPrefs.isGuestLinkWalkthroughSeen()`,
not per-property). Steps 1–2 render in the Guest Link dialog; opening Host
Chat continues into steps 3–9 there.

### Steps 1–2 — `frontend/lib/widgets/generate_guest_link_dialog.dart`

Panel: `_WalkthroughTip` class. Docked beside the dialog card (desktop only,
≥1000px — below that, falls back to a plain `AlertDialog` with no tip at all).
No per-field glow highlight here — the guest-name field is pre-filled with
"Test walkthrough" instead.

| Step | Header | Body |
|---|---|---|
| GUEST LINK · 1 of 9 | *(eyebrow only, no separate title)* | I've filled in a test name — hit Generate Link and I'll create real links you can use to message me yourself, as a guest. |
| GUEST LINK · 2 of 9 | *(eyebrow only, no separate title)* | Send whichever matches how your guest reaches out — web, WhatsApp, or Telegram, they all reach me the same way. One more thing to show you first → |

### Steps 3–9 — `frontend/lib/widgets/chat_live_dialog.dart`

State: `_wtStep` (0–6, displayed as step+3 of 9), `_wtStepInfo(step)`.
Counter label built as `'${step + 3} of 9'`. Marks the *whole* Part C
walkthrough seen (`WalkthroughPrefs`) once this sequence finishes here —
that's why Part B tracks its own "seen" flag but Part C's is only ever
written from this file, never from the Guest Link dialog.

| Step | Highlights (GlobalKey) | Header | Body |
|---|---|---|---|
| 3 of 9 | `_wtHeaderKey` | Always know who and where | This is my live view of that guest's conversation — the header always shows the property and who's booked. |
| 4 of 9 | `_wtLinksKey` | Same links, right here too | Handy to resend without leaving this view. |
| 5 of 9 | `_wtModeKey` + `_wtPillKey` | Right now, I'm on Autopilot | I'm handling this conversation myself. Watch what happens when a guest asks something I'm not fully confident about → |
| 6 of 9 | `_wtModeKey` + `_wtPillKey` | Escalated — I flagged this for you | I switch us to Intervene automatically whenever something needs your OK, or anything I'm not confident about. You can also flip to Intervene yourself anytime, escalation or not. *(triggers a real escalation on entry — `onEnter: _wtTriggerEscalation`)* |
| 7 of 9 | `_wtResolveKey` | Your turn | I've drafted a reply below — hit Send first. Once it's sent, click Mark Issue as Resolved so I can resume control — resolving before the guest actually has an answer would leave them hanging. *(pre-fills a draft reply on entry — `onEnter: _wtPrefillReply`; this is the `finalStep` — Back is disabled after it)* |
| 8 of 9 | *(none)* | All yours again | Nice work — I've resumed handling this conversation myself. Questions along the way? Check the FAQ. Want to run through everything again sometime? The full tutorial's always in the Host Setup Guide. *(Back hidden from here on)* |
| 9 of 9 | *(none)* | See it from both sides | Now, go use the test links you already generated — use your preferred channel link and talk to me as if you were the guest, and see both sides in action. *(`closingStep: true` — this is the actual end of the whole Part C sequence)* |

**Keep:** the `_wtHighlight()` glow wrapper in `chat_live_dialog.dart` (same
purple border/shadow pattern, independently duplicated in this file) around
`_wtHeaderKey`, `_wtPillKey`, `_wtLinksKey`, `_wtModeKey`, `_wtResolveKey`.

**Remove:** the `_WalkthroughTip` class and its docked-panel usage in
`generate_guest_link_dialog.dart`; the tip-rendering block (around line
750–800, the `GlassPanel` + step-counter + title/body `Text`/`SelectableText`
widgets) in `chat_live_dialog.dart`; both files' `_wtStep`/state-machine
plumbing for stepping through 1–9 and advancing/closing.

---

## Loose ends carried over from this session (not part of the copy, but relevant to the rebuild)

- Settings' docked panel disappears entirely below 1000px viewport width —
  confirmed live on a phone. Whatever replaces it should have an actual
  mobile fallback, not silently drop the tip.
- The rendering bug reproduced identically across two different physical
  machines/browsers, was unaffected by incognito mode, blur radius, or
  `RepaintBoundary` isolation, and `chrome://accessibility` showed no
  assistive technology attached to the page at all — so whatever it was, it
  wasn't ruled machine/extension-specific or pinned down structurally either.
  Treat as unexplained, not diagnosed.
