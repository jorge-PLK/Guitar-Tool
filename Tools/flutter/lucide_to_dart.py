#!/usr/bin/env python3
"""Convierte los iconos de ToneForge (Lucide, trazo 24x24) a constantes Dart.

Lee SVG de Lucide (path, circle, rect, line, polyline, polygon) y los SVG
propios de CUSTOM, y escribe los comandos de Path (_M, _L, _C, _A, _Z) en
FlutterApp/lib/theme/icons_data.dart e icons_data_2.dart. Solo stdlib.

Uso (desde la raiz del repo):
  python3 -I Tools/flutter/lucide_to_dart.py \
      --lucide <carpeta con los SVG de Lucide 1.70.0> \
      --out FlutterApp/lib/theme \
      --version 1.70.0
"""
import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

# (simbolo SF, valor del enum TfIcon, fuente). Fuente: nombre Lucide o 'custom:<nombre>'.
# El orden fija el reparto entre icons_data.dart (primeros 28) e icons_data_2.dart.
MAP = [
    ("music.note.list", "musicNoteList", "list-music"),
    ("slider.vertical.3", "sliderVertical3", "sliders-vertical"),
    ("music.quarternote.3", "musicQuarternote3", "custom:quarter-note"),
    ("record.circle", "recordCircle", "circle-dot"),
    ("film", "film", "film"),
    ("gearshape", "gearshape", "settings"),
    ("magnifyingglass", "magnifyingglass", "search"),
    ("xmark", "xmark", "x"),
    ("trash", "trash", "trash"),
    ("folder", "folder", "folder"),
    ("pencil", "pencil", "pencil"),
    ("chevron.left", "chevronLeft", "chevron-left"),
    ("chevron.down", "chevronDown", "chevron-down"),
    ("checkmark.circle", "checkmarkCircle", "circle-check"),
    ("info.circle", "infoCircle", "info"),
    ("exclamationmark.triangle", "exclamationmarkTriangle", "triangle-exclamation-point"),
    ("arrow.up.right.square", "arrowUpRightSquare", "square-arrow-out-up-right"),
    ("play.fill", "playFill", "play"),
    ("arrow.uturn.backward", "arrowUturnBackward", "undo-2"),
    ("arrow.uturn.forward", "arrowUturnForward", "redo-2"),
    ("plus", "plus", "plus"),
    ("minus", "minus", "minus"),
    ("arrow.up.arrow.down", "arrowUpArrowDown", "arrow-up-down"),
    ("person.fill", "personFill", "user"),
    ("music.note", "musicNote", "custom:music-note"),
    ("xmark.circle.fill", "xmarkCircleFill", "circle-x"),
    ("checkmark.circle.fill", "checkmarkCircleFill", "circle-check"),
    ("exclamationmark.triangle.fill", "exclamationmarkTriangleFill", "triangle-exclamation-point"),
    ("chevron.right", "chevronRight", "chevron-right"),
    ("chevron.up", "chevronUp", "chevron-up"),
    ("chevron.up.chevron.down", "chevronUpChevronDown", "chevrons-up-down"),
    ("checkmark", "checkmark", "check"),
    ("checkmark.square.fill", "checkmarkSquareFill", "square-check"),
    ("square", "square", "square"),
    ("circle", "circle", "circle"),
    ("largecircle.fill.circle", "largecircleFillCircle", "circle-dot"),
    ("pencil.circle.fill", "pencilCircleFill", "square-pen"),
    ("pause.fill", "pauseFill", "pause"),
    ("playpause.fill", "playpauseFill", "custom:play-pause"),
    ("backward.end.fill", "backwardEndFill", "skip-back"),
    ("repeat", "repeat", "repeat"),
    ("arrow.left", "arrowLeft", "arrow-left"),
    ("arrow.right", "arrowRight", "arrow-right"),
    ("video", "video", "video"),
    ("camera.fill", "cameraFill", "camera"),
    ("lock.fill", "lockFill", "lock"),
    ("rotate.right", "rotateRight", "rotate-cw"),
    ("line.3.horizontal", "line3Horizontal", "menu"),
    ("guitars", "guitars", "guitar"),
    ("guitars.fill", "guitarsFill", "guitar"),
    ("waveform", "waveform", "audio-waveform"),
    ("mic", "mic", "mic"),
    ("circle.grid.2x2", "circleGrid2x2", "layout-grid"),
    ("speaker.wave.2.fill", "speakerWave2Fill", "volume-2"),
    ("speaker.slash.fill", "speakerSlashFill", "volume-x"),
    ("rectangle.dashed", "rectangleDashed", "square-dashed"),
]

# Iconos que Lucide 1.70.0 no trae; se dibujan con el mismo trazo (24x24, stroke 2).
CUSTOM = {
    "music-note": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
    "quarter-note": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M9 18V4l5 4"/><circle cx="6" cy="18" r="3"/></svg>',
    "play-pause": '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M3 6v12l7-6z"/><path d="M15 6v12"/><path d="M20 6v12"/></svg>',
}

CHUNK = 14

NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
SEP = re.compile(r"[\s,]*")


class Reader:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def skip(self):
        self.i = SEP.match(self.s, self.i).end()

    def more(self):
        self.skip()
        return self.i < len(self.s)

    def num(self):
        self.skip()
        m = NUM.match(self.s, self.i)
        if not m:
            raise ValueError("numero esperado en %r pos %d" % (self.s, self.i))
        self.i = m.end()
        return float(m.group())

    def flag(self):
        # Las banderas de arco pueden ir pegadas ("0011"): se leen de un caracter.
        self.skip()
        c = self.s[self.i]
        if c not in "01":
            raise ValueError("bandera de arco esperada en %r pos %d" % (self.s, self.i))
        self.i += 1
        return c == "1"


def parse_path(d):
    """Convierte un atributo d de SVG a comandos absolutos M, L, C, A, Z."""
    r = Reader(d)
    out = []
    cx = cy = 0.0
    sx = sy = 0.0
    ccx = ccy = None  # ultimo punto de control cubico (para S)
    qcx = qcy = None  # ultimo punto de control cuadratico (para T)
    cmd = None
    while r.more():
        ch = d[r.i]
        if ch.isalpha():
            cmd = ch
            r.i += 1
            if cmd in "Zz":
                out.append(("Z",))
                cx, cy = sx, sy
                ccx = ccy = qcx = qcy = None
                continue
        elif cmd is None or cmd in "Zz":
            raise ValueError("comando SVG esperado en %r" % d)
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if c == "M":
            x = r.num() + ox
            y = r.num() + oy
            out.append(("M", x, y))
            cx, cy = sx, sy = x, y
            cmd = "l" if rel else "L"
            ccx = ccy = qcx = qcy = None
        elif c == "L":
            x = r.num() + ox
            y = r.num() + oy
            out.append(("L", x, y))
            cx, cy = x, y
            ccx = ccy = qcx = qcy = None
        elif c == "H":
            x = r.num() + (cx if rel else 0.0)
            out.append(("L", x, cy))
            cx = x
            ccx = ccy = qcx = qcy = None
        elif c == "V":
            y = r.num() + (cy if rel else 0.0)
            out.append(("L", cx, y))
            cy = y
            ccx = ccy = qcx = qcy = None
        elif c == "C":
            x1 = r.num() + ox
            y1 = r.num() + oy
            x2 = r.num() + ox
            y2 = r.num() + oy
            x = r.num() + ox
            y = r.num() + oy
            out.append(("C", x1, y1, x2, y2, x, y))
            ccx, ccy = x2, y2
            cx, cy = x, y
            qcx = qcy = None
        elif c == "S":
            x2 = r.num() + ox
            y2 = r.num() + oy
            x = r.num() + ox
            y = r.num() + oy
            if ccx is None:
                x1, y1 = cx, cy
            else:
                x1, y1 = 2 * cx - ccx, 2 * cy - ccy
            out.append(("C", x1, y1, x2, y2, x, y))
            ccx, ccy = x2, y2
            cx, cy = x, y
            qcx = qcy = None
        elif c == "Q":
            qx = r.num() + ox
            qy = r.num() + oy
            x = r.num() + ox
            y = r.num() + oy
            out.append(quad_to_cubic(cx, cy, qx, qy, x, y))
            qcx, qcy = qx, qy
            cx, cy = x, y
            ccx = ccy = None
        elif c == "T":
            x = r.num() + ox
            y = r.num() + oy
            if qcx is None:
                qx, qy = cx, cy
            else:
                qx, qy = 2 * cx - qcx, 2 * cy - qcy
            out.append(quad_to_cubic(cx, cy, qx, qy, x, y))
            qcx, qcy = qx, qy
            cx, cy = x, y
            ccx = ccy = None
        elif c == "A":
            rx = r.num()
            ry = r.num()
            rot = r.num()
            large = r.flag()
            sweep = r.flag()
            x = r.num() + ox
            y = r.num() + oy
            out.append(("A", rx, ry, rot, large, sweep, x, y))
            cx, cy = x, y
            ccx = ccy = qcx = qcy = None
        else:
            raise ValueError("comando SVG no soportado: %s" % cmd)
    return out


def quad_to_cubic(x0, y0, qx, qy, x, y):
    return (
        "C",
        x0 + 2.0 / 3.0 * (qx - x0),
        y0 + 2.0 / 3.0 * (qy - y0),
        x + 2.0 / 3.0 * (qx - x),
        y + 2.0 / 3.0 * (qy - y),
        x,
        y,
    )


def num_list(text):
    return [float(v) for v in NUM.findall(text)]


def shape_to_cmds(el):
    tag = el.tag.split("}")[-1]
    a = el.attrib
    if tag == "path":
        return parse_path(a["d"])
    if tag == "circle":
        cx, cy, rr = float(a["cx"]), float(a["cy"]), float(a["r"])
        return [
            ("M", cx + rr, cy),
            ("A", rr, rr, 0.0, True, True, cx - rr, cy),
            ("A", rr, rr, 0.0, True, True, cx + rr, cy),
            ("Z",),
        ]
    if tag == "line":
        return [
            ("M", float(a["x1"]), float(a["y1"])),
            ("L", float(a["x2"]), float(a["y2"])),
        ]
    if tag in ("polyline", "polygon"):
        pts = num_list(a["points"])
        cmds = [("M", pts[0], pts[1])]
        for k in range(2, len(pts), 2):
            cmds.append(("L", pts[k], pts[k + 1]))
        if tag == "polygon":
            cmds.append(("Z",))
        return cmds
    if tag == "rect":
        x, y = float(a.get("x", 0)), float(a.get("y", 0))
        w, h = float(a["width"]), float(a["height"])
        rx = float(a.get("rx", 0))
        ry = float(a.get("ry", rx))
        if rx == 0 or ry == 0:
            return [
                ("M", x, y),
                ("L", x + w, y),
                ("L", x + w, y + h),
                ("L", x, y + h),
                ("Z",),
            ]
        return [
            ("M", x + rx, y),
            ("L", x + w - rx, y),
            ("A", rx, ry, 0.0, False, True, x + w, y + ry),
            ("L", x + w, y + h - ry),
            ("A", rx, ry, 0.0, False, True, x + w - rx, y + h),
            ("L", x + rx, y + h),
            ("A", rx, ry, 0.0, False, True, x, y + h - ry),
            ("L", x, y + ry),
            ("A", rx, ry, 0.0, False, True, x + rx, y),
            ("Z",),
        ]
    raise ValueError("elemento SVG no soportado: %s" % tag)


def svg_to_cmds(root):
    """Comandos de Path de un elemento SVG raiz (ya parseado)."""
    cmds = []
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag in ("svg", "g", "title", "desc"):
            continue
        cmds.extend(shape_to_cmds(el))
    return cmds


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def dart_cmd(c):
    k = c[0]
    if k == "M":
        return "_M(%s, %s)" % (fmt(c[1]), fmt(c[2]))
    if k == "L":
        return "_L(%s, %s)" % (fmt(c[1]), fmt(c[2]))
    if k == "C":
        return "_C(%s, %s, %s, %s, %s, %s)" % tuple(fmt(v) for v in c[1:])
    if k == "A":
        return "_A(%s, %s, %s, %s, %s, %s, %s)" % (
            fmt(c[1]),
            fmt(c[2]),
            fmt(c[3]),
            "true" if c[4] else "false",
            "true" if c[5] else "false",
            fmt(c[6]),
            fmt(c[7]),
        )
    return "_Z()"


def write_part(path, var, entries, version):
    lines = [
        "// Generado por Tools/flutter/lucide_to_dart.py desde Lucide %s (ISC)." % version,
        "// No editar a mano: regenerar con el script.",
        "part of 'icons.dart';",
        "",
        "const Map<TfIcon, List<_Cmd>> %s = {" % var,
    ]
    for sf, enum, cmds in entries:
        lines.append("  // %s" % sf)
        lines.append("  TfIcon.%s: [" % enum)
        for c in cmds:
            lines.append("    %s," % dart_cmd(c))
        lines.append("  ],")
    lines.append("};")
    lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lucide", required=True, help="carpeta con <nombre>.svg de Lucide")
    ap.add_argument("--out", required=True, help="carpeta de salida (lib/theme)")
    ap.add_argument("--version", required=True, help="version de Lucide para la cabecera")
    args = ap.parse_args()

    enums = [m[1] for m in MAP]
    if len(MAP) != 56 or len(set(enums)) != len(enums):
        sys.exit("MAP debe tener 56 entradas con valores de enum unicos")

    entries = []
    for sf, enum, src in MAP:
        if src.startswith("custom:"):
            name = src[len("custom:"):]
            if name not in CUSTOM:
                sys.exit("falta el SVG propio: %s" % name)
            root = ET.fromstring(CUSTOM[name])
        else:
            svg = os.path.join(args.lucide, src + ".svg")
            if not os.path.isfile(svg):
                sys.exit("falta el SVG de Lucide: %s" % svg)
            root = ET.parse(svg).getroot()
        cmds = svg_to_cmds(root)
        if not cmds:
            sys.exit("sin comandos para %s" % sf)
        entries.append((sf, enum, cmds))

    # Cuatro partes de 14 iconos para no pasar de ~300 lineas por fichero.
    parts = []
    for n, start in enumerate(range(0, len(entries), CHUNK)):
        name = "icons_data.dart" if n == 0 else "icons_data_%d.dart" % (n + 1)
        var = "_tfIconData%s" % chr(ord("A") + n)
        part_entries = entries[start:start + CHUNK]
        write_part(os.path.join(args.out, name), var, part_entries, args.version)
        parts.append((name, var, len(part_entries)))
    print("iconos: %d en %s" % (len(entries), ", ".join("%s (%d)" % (p[0], p[2]) for p in parts)))
    print("variables: %s" % ", ".join(p[1] for p in parts))


if __name__ == "__main__":
    main()
