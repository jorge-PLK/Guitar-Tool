"""Fase 5b: descarga la tablatura de Songsterr de un tema como verdad de referencia (solo herramienta de desarrollo).

Peticiones mínimas: 1 a la página (con cabeceras de navegador; un único reintento cortés tras 429) + 1 por pista de
guitarra/bajo al CDN de revisiones (cloudfront). La batería no se descarga. Si Songsterr bloquea, guardar la página
desde el navegador y pasarla con --html.
Formato de la URL del CDN: el de github.com/Metaphysics0/songsterr-downloader (MIT), src/lib/songsterr/revision-fetcher.ts.
Datos crudos en Temp/p5b/songsterr/<songId>/ (no se versionan; contenido con derechos: no redistribuir).

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/songsterr_fetch.py URL [--html pagina.html]
"""
import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Temp" / "p5b" / "songsterr"
CDNS = ["https://dqsljvtekg760.cloudfront.net", "https://d3d3l6a6rcgkaf.cloudfront.net"]
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/121.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
}


def get(url: str, accept: str | None = None) -> tuple[int, bytes]:
    h = dict(HEADERS, **({"Accept": accept} if accept else {}))
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""


def get_curl(url: str) -> tuple[int, bytes]:
    """Songsterr responde 103 Early Hints antes del 200 y http.client de Python 3.12 toma el 103 como respuesta
    final; curl los gestiona bien."""
    import subprocess
    cmd = ["curl", "-s", "--compressed", "--max-time", "30", "-w", "\n%{http_code}"]
    for k, v in HEADERS.items():
        cmd += ["-H", f"{k}: {v}"]
    out = subprocess.run(cmd + [url], capture_output=True).stdout
    body, _, code = out.rpartition(b"\n")
    return int(code or 0), body


def fetch_page(url: str) -> str:
    code, body = get_curl(url)
    if code == 429:
        time.sleep(30)
        code, body = get_curl(url)
    if code != 200:
        sys.exit(f"Songsterr respondió {code} a la página. Guardar la página desde el navegador y usar --html.")
    return body.decode("utf-8", "replace")


def parse_state(html: str) -> dict:
    m = re.search(r'<script[^>]*id="state"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        sys.exit("no hay <script id=\"state\"> en la página")
    raw = m.group(1).strip()
    return json.loads(urllib.parse.unquote(raw) if raw.startswith("%") else raw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--html", type=Path)
    a = ap.parse_args()
    m = re.search(r"-s(\d+)", a.url)
    cache = OUT / f"page_s{m.group(1) if m else 'x'}.html"
    if a.html:
        html = a.html.read_text()
    elif cache.exists():  # la página ya descargada: no se vuelve a pedir
        html = cache.read_text()
    else:
        html = fetch_page(a.url)
        OUT.mkdir(parents=True, exist_ok=True)
        cache.write_text(html)
    cur = parse_state(html)["meta"]["current"]
    song_id, rev, image = int(cur["songId"]), int(cur["revisionId"]), str(cur["image"])
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", image):
        sys.exit("image no válida")
    d = OUT / str(song_id)
    d.mkdir(parents=True, exist_ok=True)
    tracks = cur["tracks"]
    meta = {"url": a.url, "songId": song_id, "revisionId": rev, "image": image, "title": cur.get("title"),
            "artist": cur.get("artist"), "tracks": tracks}
    (d / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    lines = [f"songId {song_id} rev {rev}: {len(tracks)} pistas"]
    for t in tracks:
        pid = int(t["partId"])
        if t.get("isDrums") or int(t.get("instrumentId", 0)) >= 1024:
            lines.append(f"  parte {pid} {t.get('instrument')} ({t.get('title') or t.get('name')}): batería, se omite")
            continue
        dst = d / f"{pid}.json"
        if not dst.exists():
            for cdn in CDNS:
                code, body = get(f"{cdn}/{song_id}/{rev}/{image}/{pid}.json", "application/json")
                if code == 200:
                    dst.write_bytes(body)
                    break
            else:
                lines.append(f"  parte {pid}: CDN {code}")
                continue
        b = dst.read_bytes()
        if b[:2] == b"\x1f\x8b":  # el CDN sirve gzip sin Content-Encoding
            import gzip
            dst.write_bytes(gzip.decompress(b))
        lines.append(f"  parte {pid} {t.get('instrument')} ({t.get('title') or t.get('name')}): {dst.stat().st_size} B")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
