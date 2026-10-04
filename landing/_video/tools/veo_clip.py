"""Generate one Veo clip on Vertex (ADC) from a first frame and an optional last frame.

Usage (from backend/venv; the access token is fetched here and never printed):
  python veo_clip.py PROMPT_FILE OUT_MP4 --first first.jpg [--last last.jpg]
         [--model veo-3.1-lite-generate-001] [--res 720p] [--seconds 6] [--location us-central1]

Cost guard: one clip per run. List prices (video only, per second): Lite 720p $0.03, Fast 720p $0.08 / 1080p $0.10, Standard 1080p $0.20.
"""
import argparse, pathlib, subprocess, sys, time
from google import genai
from google.genai import types
from google.oauth2.credentials import Credentials

PRICE = {  # $ per second, video only, 720p / 1080p (confirm in billing)
    "veo-3.1-lite-generate-001": {"720p": 0.03, "1080p": 0.05},
    "veo-3.1-fast-generate-001": {"720p": 0.08, "1080p": 0.10},
    "veo-3.1-generate-001": {"720p": 0.20, "1080p": 0.20},
}
GCLOUD = str(pathlib.Path.home() / "google-cloud-sdk/bin/gcloud")

ap = argparse.ArgumentParser()
ap.add_argument("prompt_file")
ap.add_argument("out")
ap.add_argument("--first", required=True)
ap.add_argument("--last")
ap.add_argument("--model", default="veo-3.1-lite-generate-001")
ap.add_argument("--res", default="720p")
ap.add_argument("--seconds", type=int, default=6)
ap.add_argument("--aspect", default="16:9")
ap.add_argument("--location", default="us-central1")
ap.add_argument("--seed", type=int)
ap.add_argument("--negative", default="text, logos, watermark, subtitles, faces, fast motion, jump cuts, flicker, neon, sparkles, cartoon")
a = ap.parse_args()

tok = subprocess.check_output([GCLOUD, "auth", "print-access-token"], text=True).strip()
client = genai.Client(vertexai=True, project="alfred-prod-502215", location=a.location, credentials=Credentials(tok))

def img(p):
    return types.Image(image_bytes=pathlib.Path(p).read_bytes(), mime_type="image/jpeg")

cfg = types.GenerateVideosConfig(
    aspect_ratio=a.aspect, duration_seconds=a.seconds, resolution=a.res, number_of_videos=1,
    generate_audio=False, negative_prompt=a.negative, seed=a.seed,
    last_frame=img(a.last) if a.last else None,
)
est = PRICE.get(a.model, {}).get(a.res, 0) * a.seconds
print(f"model={a.model} res={a.res} seconds={a.seconds} location={a.location} estimate=${est:.2f}", flush=True)
try:
    op = client.models.generate_videos(model=a.model, prompt=pathlib.Path(a.prompt_file).read_text(encoding="utf-8").strip(), image=img(a.first), config=cfg)
    t0 = time.time()
    while not op.done:
        time.sleep(10)
        op = client.operations.get(op)
        print(f"  waiting {int(time.time() - t0)}s", flush=True)
except Exception as e:
    print(type(e).__name__, str(e).replace(tok, "[REDACTED]")[:700])
    sys.exit(1)

if getattr(op, "error", None):
    print("operation error:", str(op.error).replace(tok, "[REDACTED]")[:700]); sys.exit(2)
vids = getattr(op.response, "generated_videos", None) or []
if not vids:
    print("no video; response:", str(op.response)[:500]); sys.exit(3)
v = vids[0].video
data = getattr(v, "video_bytes", None)
if not data:
    print("video returned without bytes; uri:", getattr(v, "uri", None)); sys.exit(4)
pathlib.Path(a.out).write_bytes(data)
print(f"OK {a.out} bytes={len(data)} took={int(time.time() - t0)}s estimate=${est:.2f}")
