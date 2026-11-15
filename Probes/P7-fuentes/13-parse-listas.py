"""P7b: resume el __NEXT_DATA__ de embeds de lista, álbum y tema (sin volcar el JSON entero)."""
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])


def load(name):
    html = (out / f"{name}.html").read_text()
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    print(f"== {name}: __NEXT_DATA__ {bool(m)}  (html {len(html)} bytes, <title>: {re.findall('<title>(.*?)</title>', html)[:1]})")
    if not m:
        return None
    d = json.loads(m.group(1))
    (out / f"{name}_next.json").write_text(json.dumps(d, indent=1, ensure_ascii=False))
    return d


def find_lists(node, path=""):
    """Rutas de listas de dicts que parecen temas (tienen title o uri)."""
    if isinstance(node, dict):
        for k, v in node.items():
            yield from find_lists(v, f"{path}.{k}")
    elif isinstance(node, list):
        if node and isinstance(node[0], dict) and ("uri" in node[0] or "title" in node[0]):
            yield path, node
        for i, v in enumerate(node[:1]):
            yield from find_lists(v, f"{path}[{i}]")


for name in ("playlist", "album", "track7"):
    d = load(name)
    if not d:
        continue
    ent = d["props"]["pageProps"]["state"]["data"]["entity"]
    print("entity ruta: props.pageProps.state.data.entity")
    for k, v in ent.items():
        if not isinstance(v, (list, dict)):
            print(f"  {k}: {str(v)[:100]}")
        elif isinstance(v, list):
            print(f"  {k}: lista de {len(v)}")
        else:
            print(f"  {k}: dict claves {list(v)[:8]}")
    for path, lst in find_lists(ent):
        print(f"lista de temas en entity{path}: {len(lst)} entradas; claves: {sorted(lst[0])}")
        for e in lst[:2] + lst[-1:]:
            print("   ", json.dumps(e, ensure_ascii=False)[:300])
    for k in ("totalCount", "trackCount", "total", "numTracks"):
        if k in ent:
            print(f"total declarado {k}: {ent[k]}")
