import base64, json, pathlib, re, sys, time, urllib.request

SP = pathlib.Path(sys.argv[1])
envf = pathlib.Path.home() / "AG_master_files/_scripts/.env"
key = None
for line in envf.read_text().splitlines():
    m = re.match(r"^OPENROUTER_API_KEY\s*=\s*(.+)$", line.strip())
    if m:
        key = m.group(1).strip().strip("\"'")
MODELS = sys.argv[2].split(",")

BRIEF = ("Product: an AI concierge for short-term-rental hosts. Guests message via WhatsApp, Telegram or web chat; the AI answers from the host's own "
         "property knowledge (ingested from files and the Airbnb listing) and hands off to the host when unsure. Hosts get their time back. "
         "Brand name: Always Alfred (Alfred = the quiet butler persona). Audience: premium STR owners who value efficiency and peace of mind; beta is WhatsApp-first in Mexico. "
         "Existing visual draft: deep obsidian canvas, aurora gradients (purple/blue/mint), warm amber glow for 'intervene' hand-offs, glassmorphism. "
         "Tagline anchor: 'Give yourself the gift of time.'")
COMP = ("Competitor: alfredhospitalityai.com - light-mode teal site, 'AI Guest Assistant for Hospitality', from $39.99/mo per property, "
        "channels Airbnb/Booking/VRBO/WhatsApp/email/SMS/web chat, multi-language, 24/7.")
img = base64.b64encode((SP / "competitor.png").read_bytes()).decode()
TASKS = {
    "T1_vision": [{"type": "text", "text": "You are a brand design critic. This is a competitor's homepage screenshot. In under 150 words: (1) palette and type observations, (2) the layout pattern, (3) two weaknesses a rival brand could exploit. Be concrete, no filler."},
                  {"type": "image_url", "image_url": {"url": "data:image/png;base64," + img}}],
    "T2_copy": BRIEF + "\n\nWrite: (a) 3 positioning statements, max 18 words each; (b) 5 tagline options, max 6 words each. Be specific to this product. Forbidden words: seamless, revolutionize, effortless, 24/7, AI-powered, supercharge. Output only the lists.",
    "T3_strategy": BRIEF + "\n" + COMP + "\n\nIn under 170 words: (1) list the 4 visual/verbal clichés common to AI guest-messaging brands for rental hosts, (2) recommend ONE brand archetype (Innocent, Sage, Explorer, Outlaw, Magician, Hero, Lover, Jester, Everyman, Caregiver, Ruler, Creator) with a 2-sentence reason, (3) name the single biggest differentiation risk.",
}

def call(model, content, think=False):
    body = {"model": model, "max_tokens": 1800, "messages": [{"role": "user", "content": content}]}
    if not think:
        body["reasoning"] = {"enabled": False}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json", "User-Agent": "ag"})
    t = time.time()
    try:
        d = json.load(urllib.request.urlopen(req, timeout=120))
    except Exception as e:
        return {"error": str(e).replace(key, "[REDACTED]")[:200], "s": round(time.time() - t, 1)}
    u = d.get("usage", {})
    return {"text": (d["choices"][0]["message"].get("content") or "").strip(), "cost": u.get("cost"), "in": u.get("prompt_tokens"),
            "out": u.get("completion_tokens"), "s": round(time.time() - t, 1)}

res = {}
for m in MODELS:
    for tname, content in TASKS.items():
        res[f"{m}|{tname}"] = call(m, content)
(SP / "bakeoff.json").write_text(json.dumps(res, indent=1))
tot = 0
for k, v in res.items():
    print("=====", k, "| cost", v.get("cost"), "| out_tok", v.get("out"), "|", v.get("s"), "s", v.get("error", ""))
    print(v.get("text", "")[:900])
    tot += v.get("cost") or 0
print("TOTAL COST $", round(tot, 4))
