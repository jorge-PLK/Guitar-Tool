"""Fase 5b: descarga verificada del código mínimo de inferencia de Guitab y de sus pesos publicados.

Código: github.com/DanieleMorotti/guitab (MIT) en un commit fijo, verificado con el SHA-1 de blob de git.
Pesos: huggingface.co/danmor/guitab (CC BY-NC-SA 4.0: uso personal, no redistribuir) en una revisión fija,
verificados con el sha256 LFS.
Todo va a Temp/p5b/src/ (no se versiona).

MuScriptor small (HF MuScriptor/muscriptor-small) NO se descarga: el repositorio está restringido (gated) y exige
que el usuario acepte su licencia con su cuenta de HF y un token (HF_TOKEN). Si existe HF_TOKEN, solo se comprueba
el acceso (código HTTP), sin descargar.

Uso: Tools/py/.venv/bin/python Probes/P5b-guitarra/fetch.py
"""
import hashlib
import os
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "Temp" / "p5b" / "src"
GITHUB_COMMIT = "b2537dcd1ad68fa2c1cde35496a353b0a33081d6"
GITHUB_RAW = f"https://raw.githubusercontent.com/DanieleMorotti/guitab/{GITHUB_COMMIT}/"
CODE = {  # ruta -> SHA-1 de blob de git
    "guitab/__init__.py": "97afd6f0f9c98ae8f847d5b5e187de83e6fe54f7",
    "guitab/audio.py": "f1897db13bc01916e230ca57bb809883c5766b6f",
    "guitab/guitar.py": "24d11e3b130effec6e7ebfaf4982d225b8e49f18",
    "guitab/inference.py": "5b059c5c3f14d936ecd0ab8ad2707c5330de6ae3",
    "guitab/model.py": "30561bbf5ce7fde354ce87d91d89536d1bd1224f",
    "guitab/paths.py": "ffe99b627008bb68957c694cfa297d3e4359fcd0",
}
HF_REV = "883d88c9f134ca8a0db3659fc26656fd027407eb"
HF_RAW = f"https://huggingface.co/danmor/guitab/resolve/{HF_REV}/"
WEIGHTS = {  # fichero -> sha256 (LFS)
    "guitab_e25.safetensors": "9b25c6361062e6b40e4d5bb0122141b73e5e1fa82bfd850fb18575e4f3089076",
    "guitab_e19.safetensors": "b6d3528d648a6993c3f23fdd61cc62aa4156a391d3b4fca8b9fe3deed4121eae",
}
UA = {"User-Agent": "python-urllib/3 model-eval"}


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def main() -> None:
    lines = []
    for rel, sha in CODE.items():
        dst = SRC / "guitab" / rel
        if dst.exists() and hashlib.sha1(b"blob %d\0" % dst.stat().st_size + dst.read_bytes()).hexdigest() == sha:
            continue
        data = get(GITHUB_RAW + rel)
        got = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        if got != sha:
            sys.exit(f"SHA de {rel} no coincide: {got}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
    lines.append(f"código guitab @ {GITHUB_COMMIT[:7]}: {len(CODE)} ficheros verificados")
    wdir = SRC / "guitab" / "weights"  # paths.WEIGHTS = ROOT/weights
    wdir.mkdir(parents=True, exist_ok=True)
    for name, sha in WEIGHTS.items():
        dst = wdir / name
        if not (dst.exists() and hashlib.sha256(dst.read_bytes()).hexdigest() == sha):
            data = get(HF_RAW + name)
            if hashlib.sha256(data).hexdigest() != sha:
                sys.exit(f"sha256 de {name} no coincide")
            dst.write_bytes(data)
        lines.append(f"pesos {name}: {dst.stat().st_size / 1e6:.1f} MB verificados")
    tok = os.environ.get("HF_TOKEN")
    url = "https://huggingface.co/MuScriptor/muscriptor-small/resolve/main/config.json"
    req = urllib.request.Request(url, method="HEAD", headers={**UA, **({"Authorization": f"Bearer {tok}"} if tok else {})})
    try:
        code = urllib.request.urlopen(req, timeout=30).status
    except urllib.error.HTTPError as e:
        code = e.code
    lines.append(f"MuScriptor small: HTTP {code} ({'con' if tok else 'sin'} HF_TOKEN)")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
