import json, os

config_path = "/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json"
mcp_name = "supabase-the-ingestor"
project_ref = "gcxxilzfhwlsjcvtpsvj"
token = "sbp_0e5dd817147ecccf9ff3e7d023f4ae233e25db49"

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f"Error reading mcp_config.json: {e}")
    sys.exit(1)

config["mcpServers"][mcp_name] = {
    "command": "wsl",
    "args": ["env", f"SUPABASE_ACCESS_TOKEN={token}", "npx", "-y",
             "@supabase/mcp-server-supabase@latest", f"--project-ref={project_ref}"]
}
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print(f"ok: added '{mcp_name}' to mcp_config.json")

profiles_dir = "/home/santoskoy/AG_master_files/_mcp_profiles"
profile = {"base": {mcp_name: []}}
profile_path = os.path.join(profiles_dir, "the-ingestor.json")
with open(profile_path, 'w') as f:
    json.dump(profile, f, indent=2)
print("ok: created the-ingestor.json profile")
