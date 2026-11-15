"""P7 paso 1: extrae campos de embed (__NEXT_DATA__) y og:/music: de la página."""
import json
import re
import sys
from pathlib import Path

meta = Path(sys.argv[1])

html = (meta / "embed.html").read_text()
m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
print("embed __NEXT_DATA__:", bool(m))
if m:
    d = json.loads(m.group(1))
    (meta / "embed_next.json").write_text(json.dumps(d, indent=1))
    ent = d["props"]["pageProps"]["state"]["data"]["entity"]
    for k, v in ent.items():
        s = json.dumps(v, ensure_ascii=False)
        print(f"  {k}: {s[:160]}")

page = (meta / "page.html").read_text()
print("og/music tags:")
for t in re.findall(r'<meta[^>]+(?:property|name)="(?:og|music|twitter):[^>]*>', page):
    print(" ", t[:220])
