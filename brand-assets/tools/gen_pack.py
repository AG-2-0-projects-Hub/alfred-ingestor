"""Mayordommo asset pack, images 2-10 (see brand-assets/asset-plan.md). One asset per prompt, style DNA verbatim.

Run from backend/venv:  TOKEN=$(gcloud auth print-access-token) python gen_pack.py [name ...]
Skips files that already exist. Logs one JSON line per generation to prompts/_run-log.jsonl.
"""
import json, os, pathlib, sys, time
from google import genai
from google.genai import types
from google.oauth2.credentials import Credentials

A = pathlib.Path("/home/santoskoy/AG_master_files/projects/the-ingestor/brand-assets")
REFS = A / "concept" / "refs"
tok = os.environ["TOKEN"]
client = genai.Client(vertexai=True, project="alfred-prod-502215", location="global", credentials=Credentials(tok))

PALETTE = ("Aubergine #160C24, Plum Glass #25153C, Pearl #F4EFF8, Lilac Mist #BCA9D5, Amethyst #AB81F2 (only as a faint dusk-sky tint), "
           "Lantern Gold #F4B64C (the only warm light, a pale golden yellow, never orange), Bone #F4ECE0 (linen and card only).")
DNA = ("Cinematic night photography lit by one warm lantern-gold practical light (#F4B64C) visible in or near the frame, spilling softly onto plaster, "
       "stone and aged wood; all other areas fall into deep aubergine-violet dusk shadow (#160C24, #25153C), no fill, no rim light. Matte materials with "
       "visible grain: stucco, terracotta, linen, brass. 35mm lens, shallow depth of field, eye level, subject off-centre on a third. Warm gold highlights, "
       "violet shadows, low saturation outside the light, slightly lifted blacks, fine film grain. Real Mexican architecture; people only as hands or from behind.")
EXCL = ("no readable text, no signs, no logos or brand marks, no watermarks, no faces, no neon, no lens flare, no robots or sparkles, no security cameras or modern fixtures, "
        "no red or terracotta-red stripe, band or wainscot on any wall, no orange or red colour cast anywhere (the light is pale golden, not orange), "
        "no purple-blue AI glow, no stock-photo look")
LOOK = "The attached image is the approved look of this brand's photography; match its light, colour grade, materials and mood so this frame looks like it was shot on the same night."

ASSETS = {
    "02-casita-costa-noche": ("heroes/casita-costa-noche", ["anchor-approved.png"],
        "A whitewashed Cycladic-style beach house in the Mexican Caribbean at night: smooth white plaster, soft rounded edges, a clear rounded ARCH entrance with a wooden door inside it, one lit doorway glowing pale golden. Palm trees in silhouette, pale sand in front, a glimpse of calm sea, violet dusk sky.",
        "16:9 wide, the arched entrance in the right half, calm dark empty violet dusk space across the left side kept clean for a headline."),
    "03-loft-cdmx-noche": ("heroes/loft-cdmx-noche", ["anchor-approved.png"],
        "A tall old wooden double street door of a Mexico City colonial building at night, one leaf ajar, warm pale-golden light spilling from the open doorway onto the cobblestones, one wrought-iron wall lantern. Stone and plaster walls sink into aubergine-violet shadow.",
        "16:9 wide, the doorway in the right half, calm dark wall and violet shadow across the left side kept clean for a headline."),
    "04-llave-en-puerta": ("action/llave-en-puerta", ["anchor-approved.png"],
        "Close-up of a hand turning a brass key in an old iron lock on a weathered wooden door, a thin vertical line of pale golden light along the gap of the door.",
        "16:9 wide, the hand and lock in the right half, the dark wooden door filling the left side."),
    "05-telefono-boca-abajo": ("action/telefono-boca-abajo", ["anchor-approved.png"],
        "A hand setting a phone face-down on a rustic wooden table beside a lit lamp with a warm shade and a ceramic cup, evening, violet plaster wall behind. The phone screen is not visible and gives no light.",
        "16:9 wide, the table and hand in the lower right, the lamp upper centre, calm dark violet wall on the left."),
    "06-llave-laton-lino": ("detail/llave-laton-lino", ["anchor-approved.png"],
        "Macro of an antique brass key resting on pale bone-coloured (#F4ECE0) linen, a visible weave. The linen is a neutral warm off-white, clearly not pink, not brown and not grey, with soft aubergine-violet shadows in its folds. Warm side light from the left, shallow depth of field.",
        "16:9 wide, the key in the right half, soft out-of-focus linen across the left."),
    "07-farol-pared": ("detail/farol-pared", ["anchor-approved.png"],
        "A wrought-iron lantern on a rough plaster wall glowing pale golden, deep aubergine-violet shadow around it, a hint of a stone door frame at the edge.",
        "16:9 wide, the lantern in the right third, dark textured wall across the left two thirds kept clean for a headline."),
    "08-huesped-llega": ("lifestyle/huesped-llega", ["anchor-approved.png"],
        "A guest seen from behind pulling a suitcase toward a lit doorway at dusk, warm pale-golden light from inside, stone and plaster walls in aubergine-violet shadow. No face visible.",
        "16:9 wide, the doorway and guest in the right half, calm dark wall and violet shadow across the left."),
    "09-anfitrion-terraza": ("lifestyle/anfitrion-terraza", ["anchor-approved.png"],
        "A host's hands holding a ceramic cup on a stone terrace balustrade at dusk, a phone lying face-down nearby (no screen visible), soft out-of-focus violet hills and dusk sky beyond, calm and unhurried. No face visible.",
        "16:9 wide, the hands and cup in the right half, soft violet dusk landscape across the left."),
    "10-tarjeta-puerta-oro": ("extras/tarjeta-puerta-oro", ["board-hanger.png", "mark-light.png"],
        "A premium bone-coloured (#F4ECE0) cardstock door hanger with a round hole cut-out, lying on dark walnut wood. The brand mark is embossed on it exactly as in the attached logo and card references: an open arch outline in deep aubergine ink (#1B102C), a thin floor line beneath it, and a solid arched door of real gold foil (#F4B64C) inside the arch. Soft natural shadow, no glow, no other printing.",
        "16:9 wide, the card at a gentle diagonal, the embossed mark in the right half, wood grain across the left."),
}

only = set(sys.argv[1:])
log = A / "prompts" / "_run-log.jsonl"
for key, (rel, refs, subject, comp) in ASSETS.items():
    if only and key not in only and key.split("-")[0] not in only:
        continue
    out = A / (rel + ".png")
    if out.exists():
        print("skip", key); continue
    out.parent.mkdir(parents=True, exist_ok=True)
    prompt = (f"SUBJECT: {subject}\n\nCOMPOSITION: {comp}\n\n{LOOK}\n\nPALETTE: {PALETTE}\n\nSTYLE DNA: {DNA}\n\nEXCLUSIONS: {EXCL}.\n")
    (A / "prompts" / f"{key}.txt").write_text(prompt, encoding="utf-8")
    parts = [types.Part.from_bytes(data=(REFS / r).read_bytes(), mime_type="image/png") for r in refs]
    parts.append(types.Part.from_text(text=prompt))
    cfg = types.GenerateContentConfig(response_modalities=["IMAGE"], image_config=types.ImageConfig(aspect_ratio="16:9", image_size="2K"))
    try:
        r = client.models.generate_content(model="gemini-3-pro-image", contents=[types.Content(role="user", parts=parts)], config=cfg)
        img = next((p.inline_data.data for p in r.candidates[0].content.parts if getattr(p, "inline_data", None)), None)
        if img is None:
            print("NO IMAGE", key); continue
        out.write_bytes(img)
        with log.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"file": rel + ".png", "prompt": f"prompts/{key}.txt", "model": "gemini-3-pro-image (Vertex, global)", "size": "2K 16:9", "est_cost_usd": 0.134, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}) + "\n")
        print("OK", key, len(img))
    except Exception as e:
        print("FAIL", key, type(e).__name__, str(e).replace(tok, "[REDACTED]")[:300])
