from firecrawl import FirecrawlApp
import inspect

app = FirecrawlApp(api_key="x")
try:
    print("scrape_url signature:", inspect.signature(app.scrape_url))
except Exception as e:
    print("scrape_url error:", type(e).__name__)

try:
    print("scrape signature:", inspect.signature(app.scrape))
except Exception as e:
    print("scrape error:", type(e).__name__)
