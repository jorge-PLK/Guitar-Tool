"""SDR de guitarra frente al stem real, con la misma función que P4 (common/metrics.py: sdr global).

Uso:
  score.py baseline            # recalcula BS-RoFormer SW (PyTorch y Core ML gridshift) en T1-T3
  score.py est <wav> <T>       # SDR de un WAV de guitarra estimado frente a T<n>/stems/guitar.wav
Resultados en out/results/scores.jsonl (una línea por medida); log en out/score.log."""
import json
import logging
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "common"))
from metrics import load_wav, sdr, si_sdr  # noqa: E402

MAIN = Path("/Volumes/SSD Mac/Personales/Guitar Tool")
TESTAUDIO = MAIN / "Probes/testaudio/out"
SW = MAIN / "Probes/P4-modelos/bs_roformer_sw/out"
OUT = HERE / "out"
(OUT / "results").mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=OUT / "score.log", level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("score")


def score(est_path, track, label):
    est, sr = load_wav(est_path)
    ref, sr2 = load_wav(TESTAUDIO / track / "stems" / "guitar.wav")
    assert sr == sr2 == 44100, (sr, sr2)
    r = {"label": label, "track": track, "est": str(est_path),
         "sdr": sdr(est, ref), "si_sdr": si_sdr(est, ref),
         "len_est": est.shape[-1], "len_ref": ref.shape[-1], "ch": est.shape[0]}
    log.info(json.dumps(r))
    with open(OUT / "results" / "scores.jsonl", "a") as f:
        f.write(json.dumps(r) + "\n")
    return r


if __name__ == "__main__":
    if sys.argv[1] == "baseline":
        for t in ["T1", "T2", "T3"]:
            for lab, p in [("sw_torch", SW / "ref_torch" / t / "guitar.wav"),
                           ("sw_coremlpub", SW / "conv" / "coremlpub_cpu_gpu" / t / "guitar.wav")]:
                r = score(p, t, lab)
                print(f"{lab} {t}: SDR {r['sdr']:.2f} dB")
    else:
        r = score(Path(sys.argv[2]), sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "est")
        print(f"{r['label']} {r['track']}: SDR {r['sdr']:.2f} dB (SI-SDR {r['si_sdr']:.2f})")
