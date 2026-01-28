import re

TF_FILE = "network.tf"  # update if your file has a different name

with open("cf_ipv4.txt") as f:
    ipv4 = [line.strip() for line in f if line.strip()]

with open(TF_FILE, "r") as f:
    contents = f.read()

pattern = r"cloudflare_ipv4_cidrs\s*=\s*\[(.*?)\]"
replacement = "cloudflare_ipv4_cidrs = [" + ", ".join(f'"{cid}"' for cid in ipv4) + "]"

new_contents = re.sub(pattern, replacement, contents, flags=re.S)

if contents != new_contents:
    with open(TF_FILE, "w") as f:
        f.write(new_contents)
    print("Updated Cloudflare IPv4 CIDRs in Terraform file.")
else:
    print("No updates needed.")
