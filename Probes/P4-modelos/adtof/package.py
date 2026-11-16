"""Fase 5 · parte 1: empaqueta el ADTOF Core ML FP32 con GRU nativa para embeberlo en la app (como BTC y Basic Pitch).

Uso:
  Tools/py/.venv/bin/python Probes/P4-modelos/adtof/package.py            # comprueba y deja el zip en out/fase5/
  Tools/py/.venv/bin/python Probes/P4-modelos/adtof/package.py --install  # además lo copia a App/Resources/Models

Parte de out/conv/adtof_fp32n.mlpackage (lo genera `convert.py --prec fp32 --gru native`, o `run_all.py --convert`).
Comprueba que es el bueno (FP32 sin tensores FP16, op MIL `gru` nativa sin `while_loop`, macOS 15, entrada `spec`
(1, T, 84, 1) T 100..60000, salida `act`), lo copia como ADTOF_FrameRNN_fp32.mlpackage con fecha fija y lo
comprime con ditto sin AppleDouble: el zip sale idéntico en cada ejecución mientras no se reconvierta el modelo.
Log en out/logs/package.log.
"""
import argparse
import collections
import json
import os
import shutil
import subprocess
from pathlib import Path

import ad_common as C

SRC = C.OUT / "conv" / "adtof_fp32n.mlpackage"
PACKAGE_NAME = "ADTOF_FrameRNN_fp32.mlpackage"
DEST = C.OUT / "fase5"
APP_MODELS = C.ROOT / "App" / "Resources" / "Models"
FIXED_MTIME = 1_700_000_000


def inspect(log) -> dict:
    import coremltools as ct
    spec = ct.utils.load_spec(str(SRC))
    fn = spec.mlProgram.functions["main"]
    ops = collections.Counter()
    for blk in fn.block_specializations.values():
        stack = list(blk.operations)
        while stack:
            op = stack.pop()
            ops[op.type] += 1
            for b in op.blocks:
                stack.extend(b.operations)
    text = str(spec.mlProgram)
    inp = spec.description.input[0]
    out = spec.description.output[0]
    rng = [(r.lowerBound, r.upperBound) for r in inp.type.multiArrayType.shapeRange.sizeRanges]
    info = {"spec_version": spec.specificationVersion, "opset": list(fn.opset), "ops": dict(ops),
            "fp16_tensors": text.count("FLOAT16"), "input": inp.name, "input_shape": list(inp.type.multiArrayType.shape),
            "input_ranges": rng, "output": out.name, "short_description": spec.description.metadata.shortDescription}
    log.info("inspección %s", json.dumps(info))
    assert info["fp16_tensors"] == 0, "no es FP32"
    assert ops.get("gru", 0) >= 1 and ops.get("while_loop", 0) == 0, "no lleva la gru nativa"
    assert "CoreML8" in info["opset"] or spec.specificationVersion >= 9, "no es macOS 15"
    assert inp.name == "spec" and out.name == "act"
    assert rng == [(1, 1), (100, 60000), (84, 84), (1, 1)], rng
    return info


def make_zip(log) -> Path:
    pkg = DEST / PACKAGE_NAME
    if pkg.exists():
        shutil.rmtree(pkg)
    DEST.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SRC, pkg)
    for root, dirs, files in os.walk(pkg):
        for n in files + dirs:
            os.utime(Path(root) / n, (FIXED_MTIME, FIXED_MTIME))
    os.utime(pkg, (FIXED_MTIME, FIXED_MTIME))
    z = DEST / f"{PACKAGE_NAME}.zip"
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
    log = C.setup_log("package")
    info = inspect(log)
    z = make_zip(log)
    zsha, zbytes = C.sha256(z), z.stat().st_size
    res = {"zip": z.name, "sha256": zsha, "bytes": zbytes, "inspect": info}
    (DEST / "package.json").write_text(json.dumps(res, indent=1))
    log.info("%s", json.dumps(res))
    if a.install:
        shutil.copy2(z, APP_MODELS / z.name)
    print(f"ops {info['ops']} · fp16 {info['fp16_tensors']} · spec v{info['spec_version']}")
    print(f"{z.name}: {zbytes} B sha256 {zsha}" + ("  [instalado]" if a.install else ""))


if __name__ == "__main__":
    main()
