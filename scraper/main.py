import os
from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
from firecrawl import FirecrawlApp
from google import genai

app = FastAPI(title="Alfred Airbnb Scraper")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


def get_firecrawl_client():
    key = os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="FIRECRAWL_API_KEY not configured")
    return FirecrawlApp(api_key=key)


def get_gemini_client():
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")
    return genai.Client(api_key=key)


def get_supabase_client():
    """Return a Supabase client scoped to the Ingestor project. (REQ-27)"""
    from supabase import create_client
    url = os.environ.get("INGESTOR_SUPABASE_URL")
    key = os.environ.get("INGESTOR_SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise RuntimeError("INGESTOR_SUPABASE_URL or INGESTOR_SUPABASE_SERVICE_KEY not configured")
    return create_client(url, key)


class ScrapeRequest(BaseModel):
    url: str


def fire_make_webhook(url: str, result: str):
    """Fire-and-forget webhook to Make.com. Non-critical path. (REQ-29)"""
    webhook_url = os.environ.get("MAKE_WEBHOOK_URL")
    if not webhook_url:
        print("Warning: MAKE_WEBHOOK_URL not set. Skipping webhook.")
        return
    payload = {"url": url, "output_markdown": result, "status": "success"}
    try:
        httpx.post(webhook_url, json=payload, timeout=5.0)
    except Exception as e:
        print(f"Make.com webhook failed (non-critical): {e}")


def upsert_to_ingestor_supabase(url: str, structured_output: str):
    """Write scraped_markdown to Ingestor Supabase via UPSERT on airbnb_url. (REQ-27)"""
    try:
        client = get_supabase_client()
        from datetime import datetime, timezone
        client.table("properties").upsert(
            {
                "airbnb_url": url,
                "scraped_markdown": structured_output,
                "status": "Scraped",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="airbnb_url",
        ).execute()
    except Exception as e:
        print(f"Ingestor Supabase upsert failed (non-critical): {e}")


def get_gemini_prompt(markdown_data: str) -> str:
    prompt_path = os.path.join(os.path.dirname(__file__), "GEMINI_PROMPT_AIRBNB.md")
    try:
        with open(prompt_path, "r", encoding="utf-8") as f:
            template = f.read()
    except FileNotFoundError:
        template = "Please analyze the following data:\n[INSERT_DATA_HERE]"
    return template.replace("[INSERT_DATA_HERE]", markdown_data)


@app.post("/scrape")
async def scrape_airbnb(req: ScrapeRequest, background_tasks: BackgroundTasks):
    """
    1. Firecrawl scrapes the Airbnb listing → raw markdown.
    2. Gemini structures the markdown into the canonical format.
    3. Upserts scraped_markdown to Ingestor Supabase directly (REQ-27).
    4. Fires Make.com webhook in background (REQ-29, non-critical).
    5. Returns structured output to caller.
    """
    url = req.url
    print(f"Starting scrape for URL: {url}")

    # 1. Firecrawl extraction
    try:
        fc = get_firecrawl_client()
        scrape_result = fc.scrape(url, formats=["markdown"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Firecrawl extraction failed: {str(e)}")

    extracted_markdown = getattr(scrape_result, "markdown", "")
    if not extracted_markdown:
        raise HTTPException(status_code=500, detail="Firecrawl returned empty markdown content")

    # 2. Gemini structuring
    try:
        client = get_gemini_client()
        final_prompt = get_gemini_prompt(extracted_markdown)
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=final_prompt,
            config=genai.types.GenerateContentConfig(
                system_instruction=(
                    "You are an expert Data Architect for vacation rental systems. "
                    "You strictly follow instructions to output structured Markdown."
                ),
                temperature=0.0,
            ),
        )
        structured_output = response.text
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gemini API processing failed: {str(e)}")

    # 3. Write to Ingestor Supabase (REQ-27) — failures are non-fatal and logged
    upsert_to_ingestor_supabase(url, structured_output)

    # 4. Make.com webhook in background (REQ-29)
    background_tasks.add_task(fire_make_webhook, url, structured_output)

    # 5. Return to caller
    return {"status": "success", "data": structured_output}


@app.get("/health")
def health_check():
    return {"status": "ok"}
