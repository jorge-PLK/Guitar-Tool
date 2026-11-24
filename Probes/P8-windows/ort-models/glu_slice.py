"""Post-proceso de los ONNX de Windows: GLU con Split -> GLU con dos Slice (mismo cálculo, bit a bit en CPU).

ONNX Runtime + DirectML, con la fusión de grafo activa y los metacomandos de NVIDIA, calcula mal el GLU
`Split(2) -> Mul(a, Sigmoid(b))` tras un MatMul+Add (SNR ~0 dB en BS-RoFormer y en el lead/rhythm; RTX 3060,
DirectML 1.15.4, driver 621.24, 22/11/2026). Cambiando el Split por dos Slice sale exacto y a la misma velocidad.
Los export nuevos ya salen así (Probes/P4-modelos/common/slice_glu.py); esto arregla los ya exportados o
publicados (BS-RoFormer T=345 es el ONNX de elicwhite) y sirve de comprobación.

Uso:
  glu_slice.py rewrite <entrada.onnx> <salida.onnx> [--verify]
      Reescribe (determinista: mismo fichero de entrada -> mismos bytes). Si no hay GLU con Split, copia tal
      cual. --verify: con el manifest.txt junto a la entrada (formato ort-smoke), compara en CPU original frente
      a nuevo y, si hay DirectML, nuevo en DML (fusión activa) frente a original en CPU.
  glu_slice.py check <modelo.onnx> [...]
      Cuenta los GLU con Split que quedan; sale con código 1 si alguno tiene.
Log en out/glu_slice.log; por consola, un resumen."""
import argparse
import hashlib
import logging
import shutil
import sys
import time
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

OUT = Path(__file__).resolve().parent / "out"
log = logging.getLogger("glu_slice")
log.setLevel(logging.INFO)
log.propagate = False

META_KEY = "toneforge.glu_slice"


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 22), b""):
            h.update(b)
    return h.hexdigest()


def find_glu(g: onnx.GraphProto) -> list:
    """[(split, idx_a, idx_b)] de cada Split de 2 salidas cuya salida b solo va a un Sigmoid y cuyo Mul junta a y
    Sigmoid(b)."""
    cons = {}
    for n in g.node:
        for i in n.input:
            cons.setdefault(i, []).append(n)
    found = []
    for n in g.node:
        if n.op_type != "Split" or len(n.output) != 2:
            continue
        for ia, ib in ((0, 1), (1, 0)):
            cb = cons.get(n.output[ib], [])
            if len(cb) != 1 or cb[0].op_type != "Sigmoid":
                continue
            sig = cb[0].output[0]
            if any(c.op_type == "Mul" and set(c.input) == {n.output[ia], sig} for c in cons.get(n.output[ia], [])):
                found.append((n, ia, ib))
                break
    return found


def split_sizes(g: onnx.GraphProto, n: onnx.NodeProto, axis: int, dims: dict, prod: dict, inits: dict) -> list:
    consts = {x.output[0]: x for x in g.node if x.op_type == "Constant"}

    def cval(name):
        if name in inits:
            return numpy_helper.to_array(inits[name])
        return numpy_helper.to_array(consts[name].attribute[0].t)

    if len(n.input) > 1 and n.input[1]:
        return [int(v) for v in cval(n.input[1]).tolist()]
    attr = [a for a in n.attribute if a.name == "split"]
    if attr:
        return list(attr[0].ints)
    d = dims.get(n.input[0])
    if d and len(d) > abs(axis) - (axis < 0) and d[axis] > 0:
        return [d[axis] // 2, d[axis] // 2]
    # igual a la anchura del MatMul(+Add) que lo alimenta
    p = prod.get(n.input[0])
    if p is not None and p.op_type == "Add":
        p = next((prod[i] for i in p.input if i in prod and prod[i].op_type == "MatMul"), None)
    if p is not None and p.op_type == "MatMul" and p.input[1] in inits:
        w = inits[p.input[1]].dims[-1]
        return [w // 2, w // 2]
    raise ValueError(f"no sé el tamaño del Split {n.name}")


def rewrite(mp: onnx.ModelProto) -> int:
    g = mp.graph
    glus = find_glu(g)
    if not glus:
        return 0
    prod = {o: n for n in g.node for o in n.output}
    inits = {i.name: i for i in g.initializer}
    dims = {}
    if any(len(n.input) < 2 or not n.input[1] for n, _, _ in glus):
        inf = onnx.shape_inference.infer_shapes(mp)
        for vi in list(inf.graph.value_info) + list(inf.graph.input):
            dims[vi.name] = [d.dim_value for d in vi.type.tensor_type.shape.dim]
    repl, freed = {}, set()
    for k, (n, _, _) in enumerate(glus):
        axis = next((a.i for a in n.attribute if a.name == "axis"), 0)
        s0, s1 = split_sizes(g, n, axis, dims, prod, inits)
        b = f"glu_slice_{k}"
        g.initializer.extend([numpy_helper.from_array(np.array([v], np.int64), f"{b}_{t}")
                              for t, v in (("s0", 0), ("e0", s0), ("s1", s0), ("e1", s0 + s1), ("ax", axis))])
        nm = n.name or b
        repl[id(n)] = [helper.make_node("Slice", [n.input[0], f"{b}_s0", f"{b}_e0", f"{b}_ax"], [n.output[0]],
                                        name=f"{nm}_slice0"),
                       helper.make_node("Slice", [n.input[0], f"{b}_s1", f"{b}_e1", f"{b}_ax"], [n.output[1]],
                                        name=f"{nm}_slice1")]
        if len(n.input) > 1 and n.input[1]:
            freed.add(n.input[1])
    new_nodes = []
    for n in g.node:
        new_nodes += repl.get(id(n), [n])
    del g.node[:]
    g.node.extend(new_nodes)
    # quita los tamaños del Split que ya no usa nadie (inicializadores o Constant)
    used = {i for n in g.node for i in n.input} | {o.name for o in g.output}
    dead = freed - used
    keep_i = [i for i in g.initializer if i.name not in dead]
    del g.initializer[:]
    g.initializer.extend(keep_i)
    keep_n = [n for n in g.node if not (n.op_type == "Constant" and n.output[0] in dead)]
    del g.node[:]
    g.node.extend(keep_n)
    meta = [p for p in mp.metadata_props if p.key != META_KEY]
    del mp.metadata_props[:]
    mp.metadata_props.extend(meta)
    mp.metadata_props.add(key=META_KEY, value=f"v1: {len(glus)} Split -> 2 Slice")
    onnx.checker.check_model(mp)
    return len(glus)


def load_fixture(model: Path):
    man = model.parent / "manifest.txt"
    feeds, outs = {}, []
    for line in man.read_text().splitlines():
        p = line.split()
        if p and p[0] == "in":
            feeds[p[1]] = np.fromfile(model.parent / p[2], np.float32).reshape([int(x) for x in p[3].split(",")])
        elif p and p[0] == "out":
            outs.append(p[1])
    return feeds, outs


def stats(ref: np.ndarray, x: np.ndarray) -> dict:
    r, y = ref.astype(np.float64), x.astype(np.float64)
    d = np.abs(r - y)
    noise = float(np.sum(d ** 2))
    return {"max": float(d.max()), "mean": float(d.mean()), "bits_iguales": bool(np.array_equal(ref, x)),
            "snr_db": float("inf") if noise == 0 else float(10 * np.log10(np.sum(r ** 2) / noise))}


def run(path: Path, feeds: dict, outs: list, dml: bool):
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.enable_mem_pattern = False
    so.enable_cpu_mem_arena = False
    prov = [("DmlExecutionProvider", {"device_id": "0"}), "CPUExecutionProvider"] if dml else ["CPUExecutionProvider"]
    s = ort.InferenceSession(str(path), so, providers=prov)
    y = s.run(outs, feeds)
    ts = []
    for _ in range(2):
        t0 = time.perf_counter()
        s.run(outs, feeds)
        ts.append(time.perf_counter() - t0)
    del s
    return y, min(ts)


def verify(src: Path, dst: Path) -> list:
    import onnxruntime as ort
    feeds, outs = load_fixture(src if (src.parent / "manifest.txt").exists() else dst)
    lines = []
    a, ta = run(src, feeds, outs, False)
    b, tb = run(dst, feeds, outs, False)
    for name, ya, yb in zip(outs, a, b):
        r = stats(ya, yb)
        log.info("CPU nuevo vs original %s: %s (%.2f s / %.2f s)", name, r, ta, tb)
        lines.append(f"  CPU nuevo vs orig {name}: iguales={r['bits_iguales']} max={r['max']:.3g} snr={r['snr_db']:.1f} dB")
    if "DmlExecutionProvider" in ort.get_available_providers():
        c, tc = run(dst, feeds, outs, True)
        for name, ya, yc in zip(outs, a, c):
            r = stats(ya, yc)
            per = ""
            if ya.ndim == 5 and ya.shape[1] > 1:     # BS-RoFormer: SNR por stem (eje 1)
                per = " por stem " + "/".join(f"{stats(ya[:, i], yc[:, i])['snr_db']:.0f}" for i in range(ya.shape[1]))
            log.info("DML(fusión) nuevo vs CPU original %s: %s%s (%.2f s)", name, r, per, tc)
            lines.append(f"  DML nuevo vs CPU orig {name}: max={r['max']:.3g} snr={r['snr_db']:.1f} dB{per} ({tc:.2f} s)")
    return lines


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rewrite")
    r.add_argument("src", type=Path)
    r.add_argument("dst", type=Path)
    r.add_argument("--verify", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("models", type=Path, nargs="+")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    h = logging.FileHandler(OUT / "glu_slice.log", encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(h)
    log.info("=== %s", sys.argv[1:])
    if a.cmd == "check":
        bad = 0
        for p in a.models:
            n = len(find_glu(onnx.load(str(p), load_external_data=False).graph))
            bad += n > 0
            log.info("check %s: %d GLU con Split", p, n)
            print(f"{p}: {n} GLU con Split" + (" (DirectML lo calcula mal: pasar glu_slice.py rewrite)" if n else ""))
        sys.exit(1 if bad else 0)
    if a.src.resolve() == a.dst.resolve():
        sys.exit("la salida tiene que ser otro fichero (guarda el original)")
    t0 = time.perf_counter()
    mp = onnx.load(str(a.src))
    n = rewrite(mp)
    a.dst.parent.mkdir(parents=True, exist_ok=True)
    if n:
        onnx.save(mp, str(a.dst))
    else:
        shutil.copyfile(a.src, a.dst)
    del mp
    msg = [f"{a.src.name}: {n} GLU Split -> Slice en {time.perf_counter() - t0:.1f} s",
           f"  orig {a.src.stat().st_size} B sha256 {sha256(a.src)}",
           f"  nuevo {a.dst.stat().st_size} B sha256 {sha256(a.dst)}  -> {a.dst}"]
    for m in msg:
        log.info(m)
    if a.verify:
        msg += verify(a.src, a.dst)
    print("\n".join(msg))


if __name__ == "__main__":
    main()
