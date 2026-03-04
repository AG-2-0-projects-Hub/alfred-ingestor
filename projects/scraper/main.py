import os
import json
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

# Initialize clients lazily to prevent crashing on boot if keys are missing
def get_firecrawl_client():
    key = os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="FIRECRAWL_API_KEY not configured")
    return FirecrawlApp(api_key=key)

def get_gemini_client():
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")
    # The client automatically picks up GEMINI_API_KEY from the environment but we can pass it explicitly
    return genai.Client(api_key=key)
class ScrapeRequest(BaseModel):
    url: str

def fire_make_webhook(url: str, result: str):
    """
    Fire-and-forget webhook to Make.com that logs the result.
    """
    webhook_url = os.environ.get("MAKE_WEBHOOK_URL")
    if not webhook_url:
        print("Warning: MAKE_WEBHOOK_URL not set in environment. Skipping webhook.")
        return

    payload = {
        "url": url,
        "output_markdown": result,
        "status": "success"
    }

    try:
        httpx.post(webhook_url, json=payload, timeout=5.0)
    except Exception as e:
        print(f"Make.com Webhook failed: {e}")

def get_gemini_prompt(markdown_data: str) -> str:
    # Read the prompt logic we extracted from Make.com
    prompt_path = os.path.join(os.path.dirname(__file__), "GEMINI_PROMPT_AIRBNB.md")
    try:
        with open(prompt_path, "r", encoding="utf-8") as f:
            template = f.read()
    except FileNotFoundError:
        # Fallback if the file was deleted or moved
        template = "Please analyze the following data:\n[INSERT_DATA_HERE]"
    
    # Replace the placeholder with actual markdown data
    prompt = template.replace("[INSERT_DATA_HERE]", markdown_data)
    # the Make template originally expected CSV, but we are feeding markdown from Firecrawl
    # the prompt will still function well since Gemini handles markdown perfectly and we replaced the data placeholder
    return prompt

@app.post("/scrape")
async def scrape_airbnb(req: ScrapeRequest, background_tasks: BackgroundTasks):
    """
    1. Triggers Firecrawl to get Markdown of the given URL.
    2. Passes Markdown to Claude with the strict Extractor prompt.
    3. Triggers Make.com in background.
    4. Returns Structured Extracted Output immediately.
    """
    url = req.url
    print(f"Starting scrape for URL: {url}")
    
    # 1. Extraction (Firecrawl)
    try:
        fc = get_firecrawl_client()
        # In firecrawl-py v4+, scrape() uses keyword arguments and returns a Document object
        scrape_result = fc.scrape(url, formats=['markdown'])
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Firecrawl extraction failed: {str(e)}")
        
    extracted_markdown = getattr(scrape_result, 'markdown', '')
    if not extracted_markdown:
        raise HTTPException(status_code=500, detail="Firecrawl returned empty markdown content")

    # 2. Structuring (Google Gemini)
    try:
        client = get_gemini_client()
        final_prompt = get_gemini_prompt(extracted_markdown)
        
        # Gemini 3 Flash Preview processing
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=final_prompt,
            config=genai.types.GenerateContentConfig(
                system_instruction="You are an expert Data Architect for vacation rental systems. You strictly follow instructions to output structured Markdown.",
                temperature=0.0
            )
        )
        structured_output = response.text
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gemini API processing failed: {str(e)}")

    # 3. Add Background Webhook Task
    background_tasks.add_task(fire_make_webhook, url, structured_output)

    # 4. Return to Flutter immediately
    return {"status": "success", "data": structured_output}

@app.get("/health")
def health_check():
    return {"status": "ok"}

