"""Basic Pitch (spotify/basic-pitch, ICASSP 2022): descarga el modelo Core ML oficial y el ONNX de referencia
desde un commit fijo de GitHub, verifica los ficheros contra el árbol de git, resume el contrato y prepara el zip
embebible (`BasicPitch_nmp.mlpackage.zip`, mismo patrón que BTC).

No hay conversión: el `.mlpackage` es el oficial (coremltools 7.0 desde TF 2.12, FP32, mlProgram).

Uso:
  Tools/py/.venv/bin/python Probes/P4-modelos/basic_pitch/convert.py            # descarga, verifica, zip en out/
  Tools/py/.venv/bin/python Probes/P4-modelos/basic_pitch/convert.py --install  # además copia el zip a App/Resources/Models
"""
import argparse
import hashlib
import json
import logging
import os
import shutil
import subprocess
import sys
import traceback
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
SRC = OUT / "src"  # ficheros descargados (datos no confiables: sin scripts aquí)
REPO = HERE.parents[2]
APP_MODELS = REPO / "App" / "Resources" / "Models"

COMMIT = "fa5997af0a8210982619003269994a1be25eddf3"  # main 2025-11-13; el modelo no cambia desde 2024-02-27 (a5ab739)
LICENSE = "Apache-2.0"
BASE = f"https://raw.githubusercontent.com/spotify/basic-pitch/{COMMIT}/basic_pitch/saved_models/icassp_2022/"
# ruta relativa -> SHA-1 de blob de git (árbol del commit)
FILES = {
    "nmp.mlpackage/Manifest.json": "37bfe14d07213ca2d0f2485dbeeeb9decd15ada9",
    "nmp.mlpackage/Data/com.apple.CoreML/model.mlmodel": "4fa2f93d7879fc58e2dc78e7ecd95a7aaad547ae",
    "nmp.mlpackage/Data/com.apple.CoreML/weights/weight.bin": "883fcaf0519b9eddcb99edec6dcba87ed6dfdcb3",
    "nmp.onnx": "c30e5f9438e798604b7177aa26be1fe64482f767",
}
PACKAGE_NAME = "BasicPitch_nmp.mlpackage"
FIXED_MTIME = 1_700_000_000  # fecha fija para que el zip salga idéntico en cada ejecución

OUT.mkdir(exist_ok=True)
SRC.mkdir(exist_ok=True)
log = logging.getLogger("convert")
log.setLevel(logging.INFO)
log.propagate = False  # basic_pitch configura el logger raíz y lo sacaría por consola
_fh = logging.FileHandler(OUT / "convert.log", mode="w")
_fh.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
log.addHandler(_fh)


def _excepthook(t, v, tb):
    log.error("".join(traceback.format_exception(t, v, tb)))
    print(f"ERROR: {t.__name__}: {v} (ver {OUT / 'convert.log'})")


sys.excepthook = _excepthook


def git_blob_sha1(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def download() -> dict:
    sums = {}
    for rel, blob in FILES.items():
        dst = SRC / rel
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            log.info("descarga %s", BASE + rel)
            with urllib.request.urlopen(BASE + rel, timeout=60) as r:
                dst.write_bytes(r.read())
        data = dst.read_bytes()
        got = git_blob_sha1(data)
        if got != blob:
            raise RuntimeError(f"{rel}: blob {got} != {blob}")
        sums[rel] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        log.info("ok %s %d B sha256 %s", rel, len(data), sums[rel]["sha256"])
    return sums


def compare_with_pip(sums: dict) -> bool:
    try:
        import basic_pitch  # noqa: WPS433
    except Exception as e:  # pragma: no cover
        log.info("basic_pitch no instalado: %s", e)
        return False
    d = Path(basic_pitch.__file__).parent / "saved_models" / "icassp_2022"
    same = all(sha256(d / rel) == s["sha256"] for rel, s in sums.items())
    log.info("idéntico al paquete pip basic-pitch: %s (%s)", same, d)
    return same


def summarize(pkg: Path) -> dict:
    import coremltools as ct
    from collections import Counter

    m = ct.models.MLModel(str(pkg), skip_model_load=True)
    s = m.get_spec()
    f = s.mlProgram.functions["main"]
    ops = Counter(o.type for b in f.block_specializations.values() for o in b.operations)
    io = {
        "inputs": {x.name: list(x.type.multiArrayType.shape) for x in s.description.input},
        "outputs": {x.name: list(x.type.multiArrayType.shape) for x in s.description.output},
    }
    info = {"specVersion": s.specificationVersion, "opset": f.opset, "metadata": dict(m.user_defined_metadata),
            "ops": dict(ops), **io}
    log.info("contrato %s", json.dumps(info))
    return info


def make_zip() -> Path:
    pkg = OUT / PACKAGE_NAME
    if pkg.exists():
        shutil.rmtree(pkg)
    shutil.copytree(SRC / "nmp.mlpackage", pkg)
    for root, dirs, files in os.walk(pkg):
        for n in files + dirs:
            os.utime(Path(root) / n, (FIXED_MTIME, FIXED_MTIME))
    os.utime(pkg, (FIXED_MTIME, FIXED_MTIME))
    z = OUT / f"{PACKAGE_NAME}.zip"
    z.unlink(missing_ok=True)
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(pkg), str(z)],
                   check=True)
    listing = subprocess.run(["/usr/bin/unzip", "-l", str(z)], check=True, capture_output=True, text=True).stdout
    log.info("zip:\n%s", listing)
    if "._" in listing:
        raise RuntimeError("el zip lleva ficheros AppleDouble ._*")
    return z


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true", help="copia el zip a App/Resources/Models")
    a = ap.parse_args()
    sums = download()
    same_pip = compare_with_pip(sums)
    info = summarize(SRC / "nmp.mlpackage")
    z = make_zip()
    zsha, zbytes = sha256(z), z.stat().st_size
    manifest = {"source": f"github.com/spotify/basic-pitch@{COMMIT}", "license": LICENSE, "files": sums,
                "same_as_pip_0_4_0": same_pip, "zip": {"name": z.name, "sha256": zsha, "bytes": zbytes,
                                                       "package": PACKAGE_NAME}, "contract": info}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    if a.install:
        APP_MODELS.mkdir(parents=True, exist_ok=True)
        shutil.copy2(z, APP_MODELS / z.name)
        log.info("copiado a %s", APP_MODELS / z.name)
    print(f"Basic Pitch @ {COMMIT[:7]} ({LICENSE}); pip idéntico: {same_pip}")
    print(f"in {info['inputs']} -> out {info['outputs']}")
    print(f"{z.name}: {zbytes} B sha256 {zsha}" + ("  [instalado]" if a.install else ""))


if __name__ == "__main__":
    main()
