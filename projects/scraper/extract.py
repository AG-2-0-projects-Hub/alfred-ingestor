import json
import sys

with open(sys.argv[1], 'r') as f:
    d = json.load(f)

bp = d.get('blueprint', {})
out = {
    'name': bp.get('name', 'test'),
    'metadata': bp.get('metadata', {})
}
print(json.dumps(out, indent=2))
