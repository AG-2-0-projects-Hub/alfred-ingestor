import httpx
import json

payload = {"url": "https://www.airbnb.com/rooms/1032126231908846399"} # Using a different common URL or the one provided
try:
    print(f"Sending request for {payload['url']}...")
    # Timeout set to 120s since scraping and LLM formatting can take up to a minute
    response = httpx.post("http://localhost:8001/scrape", json=payload, timeout=120.0)
    print(f"Status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))
except Exception as e:
    print(f"Error: {e}")
