"""Core ML publicado por terceros: gridshiftstudio/bs-roformer-sw-coreml.
Descarga BSRoformerSW.mlpackage.zip + manifest.json + README a out/coreml_pub/, descomprime y muestra
el manifiesto y la especificación (entradas/salidas) SIN compilar ni cargar el modelo (skip_model_load).
Uso: coreml_pub.py   (lanzar con ../common/guard.py; un solo proceso pesado)"""
import hashlib
import json
import sys
import urllib.request
import zipfile

import sw_common as C

SRC = {  # nombre -> (url base, ficheros, zip, mlpackage destino, sha256 esperado del zip o None)
    "gridshift": ("https://huggingface.co/gridshiftstudio/bs-roformer-sw-coreml/resolve/main/",
                  ("manifest.json", "README.md"), "BSRoformerSW.mlpackage.zip", "BSRoformerSW.mlpackage", None),
    "sunnymead": ("https://huggingface.co/sunnymeadsound/stem-separation-models/resolve/main/bs-roformer-sw-6stem/",
                  (), "bs_roformer_6stem.mlpackage.zip", "bs_roformer_6stem.mlpackage",
                  "e4e250ad97a538d7441c37003e10a59f8ed7ca3130db6e49ff04f4bf322692e5"),
}
which = sys.argv[1] if len(sys.argv) > 1 else "gridshift"
base, extra, zname, pname, want = SRC[which]
log = C.setup_log(f"coreml_pub_{which}")
sys.excepthook = lambda t, v, tb: log.error("excepción no capturada", exc_info=(t, v, tb))
D = C.OUT / ("coreml_pub" if which == "gridshift" else f"coreml_pub_{which}")
D.mkdir(parents=True, exist_ok=True)
for fn in extra + (zname,):
    if not (D / fn).exists():
        log.info("descargando %s", fn)
        urllib.request.urlretrieve(base + fn, D / fn)
h = hashlib.sha256()
with open(D / zname, "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""):
        h.update(b)
log.info("zip sha256 %s", h.hexdigest())
if want and h.hexdigest() != want:
    raise RuntimeError(f"sha256 no coincide: {h.hexdigest()} != {want}")
pkg = D / pname
if not pkg.exists():
    with zipfile.ZipFile(D / zname) as z:
        bad = [n for n in z.namelist() if n.startswith("/") or ".." in n]
        if bad:
            raise RuntimeError(f"rutas sospechosas en el zip: {bad[:3]}")
        z.extractall(D)
    found = list(D.rglob("*.mlpackage"))
    log.info("mlpackage encontrados: %s", found)
    if found and found[0] != pkg:
        found[0].rename(pkg)

man = json.load(open(D / "manifest.json")) if (D / "manifest.json").exists() else {}
log.info("manifest: %s", json.dumps(man)[:3000])

import coremltools as ct  # noqa: E402

m = ct.models.MLModel(str(pkg), skip_model_load=True)
spec = m.get_spec()
io = []
for kind, feats in (("in", spec.description.input), ("out", spec.description.output)):
    for x in feats:
        t = x.type.multiArrayType
        io.append(f"{kind} {x.name} shape={list(t.shape)} dtype={t.dataType} desc={x.shortDescription[:200]!r}")
log.info("spec version %d; %s", spec.specificationVersion, "; ".join(io))
log.info("metadata: %s %s", spec.description.metadata.shortDescription[:300], dict(spec.description.metadata.userDefined))
size = sum(f.stat().st_size for f in pkg.rglob("*") if f.is_file())
print(f"especificación v{spec.specificationVersion}, {size / 1e6:.0f} MB")
print("\n".join(io))
print("manifest claves:", list(man)[:15])
