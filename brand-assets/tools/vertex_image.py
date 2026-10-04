"""Generate one image through Vertex ADC (Nano Banana Pro) with optional reference images.

Usage (from backend/venv, TOKEN from `gcloud auth print-access-token`, never printed):
  TOKEN=... python vertex_image.py PROMPT_FILE OUT_PNG [--aspect 16:9] [--size 2K] [--ref a.png --ref b.png]
"""
import argparse, os, pathlib, sys
from google import genai
from google.genai import types
from google.oauth2.credentials import Credentials

ap = argparse.ArgumentParser()
ap.add_argument("prompt_file")
ap.add_argument("out")
ap.add_argument("--aspect", default="16:9")
ap.add_argument("--size", default="2K")
ap.add_argument("--ref", action="append", default=[])
a = ap.parse_args()

tok = os.environ["TOKEN"]
client = genai.Client(vertexai=True, project="alfred-prod-502215", location="global", credentials=Credentials(tok))
parts = [types.Part.from_bytes(data=pathlib.Path(r).read_bytes(), mime_type="image/png") for r in a.ref]
parts.append(types.Part.from_text(text=pathlib.Path(a.prompt_file).read_text(encoding="utf-8")))
cfg = types.GenerateContentConfig(
    response_modalities=["IMAGE"],
    image_config=types.ImageConfig(aspect_ratio=a.aspect, image_size=a.size),
)
try:
    r = client.models.generate_content(model="gemini-3-pro-image", contents=[types.Content(role="user", parts=parts)], config=cfg)
except Exception as e:
    print(type(e).__name__, str(e).replace(tok, "[REDACTED]")[:400])
    sys.exit(1)
for p in r.candidates[0].content.parts:
    if getattr(p, "inline_data", None):
        pathlib.Path(a.out).write_bytes(p.inline_data.data)
        u = r.usage_metadata
        print(f"OK {a.out} bytes={len(p.inline_data.data)} usage={getattr(u, 'prompt_token_count', '?')}/{getattr(u, 'candidates_token_count', '?')}")
        sys.exit(0)
print("no image part;", [getattr(p, "text", None) for p in r.candidates[0].content.parts][:2])
sys.exit(2)
