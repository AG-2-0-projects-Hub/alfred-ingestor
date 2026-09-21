"""
Core file routing logic. Processes a single file sequentially.
Returns a Markdown string.

File type → processing path:
  PDF                  → Gemini File API → Prompt A
  Images (jpg/png/...) → Gemini File API → Prompt B
  Audio (webm/mp3/...) → Gemini File API → Prompt C
  DOCX/DOC             → python-docx native extraction → Prompt A (text)
  XLSX/CSV             → openpyxl/pandas native → Prompt D (text)
"""

import io
from docx import Document
from PIL import Image
import pandas as pd

from services import gemini_client

# Full phone-camera resolution (often 3000-4000px+ on the long edge) adds real
# inline-payload size and Gemini processing latency with no analysis benefit
# past this — this is what was stalling specific host-uploaded photos past the
# per-file timeout (confirmed live 2026-09-09: two PNGs, no exception, no
# response). Mirrors the same fix already applied to scraper-side photos.
_MAX_IMAGE_DIMENSION = 1600
_JPEG_QUALITY = 85

# MIME type map for Gemini File API uploads
_MIME_MAP = {
    "pdf": "application/pdf",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "heic": "image/heic",
    "gif": "image/gif",
    "webm": "audio/webm",
    "mp3": "audio/mp3",
    "wav": "audio/wav",
    "ogg": "audio/ogg",
    "m4a": "audio/m4a",
    "aac": "audio/aac",
}

_IMAGE_EXTS = {"jpg", "jpeg", "png", "webp", "heic", "gif"}
_AUDIO_EXTS = {"webm", "mp3", "wav", "ogg", "m4a", "aac"}
_DOCX_EXTS = {"doc", "docx"}
_SHEET_EXTS = {"xlsx", "xls", "csv"}


def _ext(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


async def process_file(filename: str, data: bytes) -> str:
    """Route file to the correct Gemini prompt. Returns Markdown."""
    ext = _ext(filename)

    if ext == "pdf":
        return await _process_document(filename, data, "pdf")

    if ext in _IMAGE_EXTS:
        return await _process_image(filename, data, ext)

    if ext in _AUDIO_EXTS:
        return await _process_audio(filename, data, ext)

    if ext in _DOCX_EXTS:
        return await _process_docx(data)

    if ext in _SHEET_EXTS:
        return await _process_sheet(filename, data, ext)

    # Fallback: treat as plain text → Prompt A
    text = data.decode("utf-8", errors="replace")
    return await gemini_client.process_with_prompt_a_text(text)


# ─── Internal helpers ─────────────────────────────────────────────────────────

async def _process_document(filename: str, data: bytes, ext: str) -> str:
    mime = _MIME_MAP.get(ext, "application/octet-stream")
    return await gemini_client.process_with_prompt_a(data, mime)


def _downscale_image(data: bytes, mime_type: str) -> tuple[bytes, str]:
    """Resize oversized images before sending to Gemini. Fails soft: any decode
    error (including formats Pillow can't open, e.g. HEIC without a plugin)
    returns the original bytes/mime unchanged rather than blocking ingestion."""
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
        if max(img.size) <= _MAX_IMAGE_DIMENSION:
            return data, mime_type
        if img.mode in ("RGBA", "LA", "P"):
            rgba = img.convert("RGBA")
            flattened = Image.new("RGB", img.size, (255, 255, 255))
            flattened.paste(rgba, mask=rgba.split()[-1])
            img = flattened
        else:
            img = img.convert("RGB")
        img.thumbnail((_MAX_IMAGE_DIMENSION, _MAX_IMAGE_DIMENSION), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=_JPEG_QUALITY)
        return out.getvalue(), "image/jpeg"
    except Exception:
        return data, mime_type


async def _process_image(filename: str, data: bytes, ext: str) -> str:
    mime = _MIME_MAP.get(ext, "image/jpeg")
    data, mime = _downscale_image(data, mime)
    return await gemini_client.process_with_prompt_b(data, mime)


async def _process_audio(filename: str, data: bytes, ext: str) -> str:
    mime = _MIME_MAP.get(ext, "audio/webm")
    return await gemini_client.process_with_prompt_c(data, mime)


async def _process_docx(data: bytes) -> str:
    doc = Document(io.BytesIO(data))
    paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
    # Also grab table cells
    for table in doc.tables:
        for row in table.rows:
            cells = [c.text.strip() for c in row.cells if c.text.strip()]
            if cells:
                paragraphs.append(" | ".join(cells))
    extracted = "\n\n".join(paragraphs)
    return await gemini_client.process_with_prompt_a_text(extracted)


async def _process_sheet(filename: str, data: bytes, ext: str) -> str:
    if ext == "csv":
        df = pd.read_csv(io.BytesIO(data))
    else:
        df = pd.read_excel(io.BytesIO(data))
    table_text = df.to_markdown(index=False) if hasattr(df, "to_markdown") else df.to_string(index=False)
    return await gemini_client.process_with_prompt_d(table_text)
