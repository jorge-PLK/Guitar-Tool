"""Pose para el encuadre en Windows: MoveNet SinglePose Thunder (ONNX) frente a Vision (VNDetectHumanBodyPoseRequest).

Uso: pose.py <dir_fotogramas> [...]   (cada dir con frame_*.png + vision.json de pose_vision.swift)
Modelo: Xenova/movenet-singlepose-thunder@38296077 onnx/model.onnx (tf2onnx de MoveNet de Google, Apache-2.0).
Se envuelve con un Cast para que la entrada sea float32 (ort-smoke y NativeONNX solo pasan float32).
Contrato: image (1,256,256,3) float32 RGB 0..255, imagen con relleno a cuadrado (resize_with_pad) ->
output_0 (1,1,17,3) = (y, x, confianza) normalizados al cuadrado de 256. Las 10 articulaciones de GuitarFramer:
COCO 9/10 muñecas, 7/8 codos, 5/6 hombros, 11/12 caderas; neck = media de hombros, root = media de caderas.
Escribe out/pose/ (model.onnx, manifest.txt, bins, mac.json, overlay_*.png) y out/pose.log."""
import hashlib
import json
import logging
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
D = HERE / "out" / "pose"
SRC = D / "dl" / "movenet_thunder.onnx"
SHA = "3dca9f6e5f8a64dc9935a5be06fd8bf81bf01e696c9c05c6f2a650e0a401b763"
URL = "https://huggingface.co/Xenova/movenet-singlepose-thunder/resolve/38296077a99667cdad67af5096ce7eeb9b327453/onnx/model.onnx"
S = 256
MIN_CONF = 0.3                     # GuitarFramer.minConfidence
COCO = {"leftWrist": 9, "rightWrist": 10, "leftElbow": 7, "rightElbow": 8, "leftShoulder": 5, "rightShoulder": 6,
        "leftHip": 11, "rightHip": 12}
log = logging.getLogger("pose")
log.setLevel(logging.INFO)
log.propagate = False
_h = logging.FileHandler(HERE / "out" / "pose.log")
_h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
log.addHandler(_h)
sys.excepthook = lambda t, v, tb: (log.error("excepción", exc_info=(t, v, tb)), print(f"ERROR {t.__name__}: {v}"))


def wrapped_model() -> Path:
    import onnx
    from onnx import TensorProto, helper
    if not SRC.exists():
        import urllib.request
        SRC.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(URL, SRC)
    if hashlib.sha256(SRC.read_bytes()).hexdigest() != SHA:
        raise RuntimeError("sha256 de MoveNet distinto")
    m = onnx.load(str(SRC))
    old = m.graph.input[0]
    assert old.name == "input" and old.type.tensor_type.elem_type == TensorProto.INT32
    m.graph.input.remove(old)
    m.graph.input.insert(0, helper.make_tensor_value_info("image", TensorProto.FLOAT, [1, S, S, 3]))
    m.graph.node.insert(0, helper.make_node("Cast", ["image"], ["input"], to=TensorProto.INT32, name="image_to_int32"))
    onnx.checker.check_model(m)
    dst = D / "model.onnx"
    onnx.save(m, str(dst))
    return dst


def letterbox(img):
    """resize_with_pad de TF: escala conservando aspecto y centra en 256x256 con ceros."""
    from PIL import Image
    w, h = img.size
    sc = S / max(w, h)
    nw, nh = round(w * sc), round(h * sc)
    canvas = Image.new("RGB", (S, S))
    px, py = (S - nw) // 2, (S - nh) // 2
    canvas.paste(img.convert("RGB").resize((nw, nh), Image.BILINEAR), (px, py))
    return np.asarray(canvas, np.float32)[None], (px, py, nw, nh)


def joints(kp, box):
    """kp (17,3) y,x,conf en el cuadrado -> {nombre: [x, y, conf]} normalizado a la imagen, origen arriba-izq."""
    px, py, nw, nh = box
    pts = {k: [(kp[i, 1] * S - px) / nw, (kp[i, 0] * S - py) / nh, float(kp[i, 2])] for k, i in COCO.items()}
    for name, (a, b) in {"neck": ("leftShoulder", "rightShoulder"), "root": ("leftHip", "rightHip")}.items():
        pa, pb = pts[a], pts[b]
        pts[name] = [(pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, min(pa[2], pb[2])]
    return {k: [float(v[0]), float(v[1]), v[2]] for k, v in pts.items() if v[2] >= MIN_CONF}


def overlay(png: Path, vis: dict, mn: dict, dst: Path):
    from PIL import Image, ImageDraw
    im = Image.open(png).convert("RGB")
    d = ImageDraw.Draw(im)
    w, h = im.size
    for pts, col in ((vis, (255, 40, 40)), (mn, (40, 255, 40))):
        for k, (x, y, *_) in pts.items():
            d.ellipse([x * w - 9, y * h - 9, x * w + 9, y * h + 9], outline=col, width=4)
            d.text((x * w + 12, y * h - 6), k, fill=col)
    im.resize((w // 2, h // 2)).save(dst)


def main():
    import onnxruntime as ort
    from PIL import Image
    path = wrapped_model()
    sess = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    log.info("ort %s in %s out %s", ort.__version__, [(i.name, i.shape, i.type) for i in sess.get_inputs()],
             [(o.name, o.shape) for o in sess.get_outputs()])
    errs, per_joint, frames, ms_all = [], {}, [], []
    only_vis = only_mn = both = 0
    first_feed = None
    for fd in map(Path, sys.argv[1:]):
        vj = json.loads((fd / "vision.json").read_text())
        for f in vj["frames"]:
            x, box = letterbox(Image.open(fd / f["png"]))
            if first_feed is None:
                first_feed = x
            sess.run(None, {"image": x})
            ts = []
            for _ in range(10):
                t0 = time.perf_counter()
                (y,) = sess.run(None, {"image": x})
                ts.append((time.perf_counter() - t0) * 1000)
            ms_all.append(float(np.median(ts)))
            mn, vis = joints(y[0, 0], box), f["joints"]
            fe = {}
            for k in set(vis) | set(mn):
                if k in vis and k in mn:
                    e = float(np.hypot(mn[k][0] - vis[k][0], mn[k][1] - vis[k][1]))
                    fe[k] = round(e, 4)
                    errs.append(e)
                    per_joint.setdefault(k, []).append(e)
                    both += 1
                elif k in vis:
                    only_vis += 1
                else:
                    only_mn += 1
            frames.append({"dir": fd.name, "t": f["t"], "vision": sorted(vis), "movenet": sorted(mn), "err": fe,
                           "ms_movenet": ms_all[-1], "ms_vision": f["ms_median"]})
            log.info("%s t=%s vision %d movenet %d err %s", fd.name, f["t"], len(vis), len(mn), fe)
            overlay(fd / f["png"], vis, mn, D / f"overlay_{fd.name}_{int(f['t'])}.png")
    # entradas y referencia fijas para ort-smoke (primer fotograma)
    first_feed.astype(np.float32).tofile(D / "in_image.bin")
    (ref,) = sess.run(None, {"image": first_feed})
    ref.astype(np.float32).tofile(D / "ref_output_0.bin")
    (D / "manifest.txt").write_text("model model.onnx\nin image in_image.bin 1,256,256,3\nout output_0 ref_output_0.bin\n")
    so = ort.SessionOptions()
    so.intra_op_num_threads = 1
    s1 = ort.InferenceSession(str(path), sess_options=so, providers=["CPUExecutionProvider"])
    s1.run(None, {"image": first_feed})
    t1 = []
    for _ in range(10):
        t0 = time.perf_counter()
        s1.run(None, {"image": first_feed})
        t1.append((time.perf_counter() - t0) * 1000)
    res = {"model": "MoveNet SinglePose Thunder (Xenova@38296077, Apache-2.0), envuelto con Cast float32",
           "size_mb": path.stat().st_size / 1e6, "opset": 11,
           "frames": len(frames), "pairs": both, "only_vision": only_vis, "only_movenet": only_mn,
           "err_mean": float(np.mean(errs)) if errs else None, "err_median": float(np.median(errs)) if errs else None,
           "err_max": float(np.max(errs)) if errs else None,
           "per_joint_mean": {k: round(float(np.mean(v)), 4) for k, v in per_joint.items()},
           "ms_cpu_median": float(np.median(ms_all)), "ms_cpu_1thread": float(np.median(t1)),
           "ms_vision_median": float(np.median([f["ms_vision"] for f in frames])), "per_frame": frames}
    (D / "mac.json").write_text(json.dumps(res, indent=1))
    print(json.dumps({k: v for k, v in res.items() if k != "per_frame"}))


main()
