import os, sys, pathlib
from google import genai
from google.oauth2.credentials import Credentials

tok = os.environ["TOKEN"]
OUT = sys.argv[1]
creds = Credentials(tok)
prompt = "A single soft warm amber glowing horizontal line on a deep obsidian-black background, diffused, minimal, no text."
for loc in ("global", "us-central1"):
    for model in ("gemini-3-pro-image-preview", "gemini-3-pro-image"):
        try:
            c = genai.Client(vertexai=True, project="alfred-prod-502215", location=loc, credentials=creds)
            r = c.models.generate_content(model=model, contents=prompt)
            for p in r.candidates[0].content.parts:
                if getattr(p, "inline_data", None):
                    pathlib.Path(OUT).write_bytes(p.inline_data.data)
                    print(f"VERTEX IMAGE OK loc={loc} model={model} bytes={len(p.inline_data.data)}")
                    sys.exit(0)
            print(loc, model, "no image part")
        except Exception as e:
            print(loc, model, type(e).__name__, str(e).replace(tok, "[REDACTED]")[:260])
