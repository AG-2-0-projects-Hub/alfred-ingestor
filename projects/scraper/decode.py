import json
import base64
import re

input_file = '/mnt/c/Users/San_8/.gemini/antigravity/brain/6c8b19bf-3ff5-4e8c-a1ff-b24f24ecd082/.system_generated/steps/231/output.txt'
output_file = '/mnt/c/Users/San_8/.gemini/antigravity/brain/6c8b19bf-3ff5-4e8c-a1ff-b24f24ecd082/.system_generated/steps/231/decoded.md'

with open(input_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

# Remove any non-base64 characters like newlines or spaces before decoding
b64_string = re.sub(r'[^A-Za-z0-9+/=]', '', data['content'])

decoded_bytes = base64.b64decode(b64_string)
decoded_str = decoded_bytes.decode('utf-8')

with open(output_file, 'w', encoding='utf-8') as f:
    f.write(decoded_str)

print("Decoded successfully")
