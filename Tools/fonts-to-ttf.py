"""Convierte los woff2 de WinApp/Web/fonts a TTF para el Mac (App/Resources/Fonts), sin tocar glifos ni métricas.
Uso: Tools/py/.venv/bin/python Tools/fonts-to-ttf.py"""
import shutil
from pathlib import Path
from fontTools.ttLib import TTFont

root = Path(__file__).resolve().parent.parent
src = root / "WinApp/Web/fonts"
dst = root / "App/Resources/Fonts"
dst.mkdir(parents=True, exist_ok=True)
for f in sorted(src.glob("*.woff2")):
    font = TTFont(f)
    font.flavor = None
    out = dst / (f.stem + ".ttf")
    font.save(out)
    n = font["name"]
    print(out.name, "|", n.getDebugName(1), "|", n.getDebugName(2), "|", n.getDebugName(4), "|", n.getDebugName(6),
          "| fvar" if "fvar" in font else "", "| glyphs", len(font.getGlyphOrder()), "| wght", font["OS/2"].usWeightClass)
for l in src.glob("LICENSE-*.txt"):
    shutil.copy(l, dst / l.name)
