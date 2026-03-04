import firecrawl
from firecrawl import FirecrawlApp
app = FirecrawlApp(api_key="x")
print([m for m in dir(app) if not m.startswith('_')])
