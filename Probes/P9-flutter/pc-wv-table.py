#!/usr/bin/env python3
"""P9 7j: tabla resumida de los informes wv-<app>-<caso>[-sufijo].json de las apps de WebView en el PC.
Uso: python3 -I pc-wv-table.py <carpeta> <app> [-sufijo]
Umbrales (los del Mac): tab = bravuraLoaded y 0 jsErrors; messages 1000/1000 sin perdidas/duplicados/desorden;
resize = innerWidth correcto y repaintedAfterResize en cada paso (salvo el primero, que no se redimensiona);
keys flutter = ninguna tecla perdida ni duplicada; songsterr = HTML > 200 kB; capture sin umbral (numeros)."""
import json
import os
import sys

CASES = ["tab", "messages", "overlay", "resize-on", "resize-off", "capture", "songsterr",
         "songsterr-offstage", "songsterr-zero", "keys-raw", "keys-flutter"]
SONGSTERR_MIN_BYTES = 200_000


def num(v, nd=1):
    return "-" if v is None else (f"{v:.{nd}f}" if isinstance(v, float) else str(v))


def verdict_bad(v):
    if not isinstance(v, dict):
        return None
    lost = sorted(k for k, x in v.items() if x == "lost")
    dup = sorted(k for k, x in v.items() if x == "duplicated")
    return lost, dup


def summarize(c, r):
    """Devuelve (pasa|NO|n/a, texto)."""
    errs = len(r.get("jsErrors") or [])
    if c == "tab":
        ok = bool(r.get("bravuraLoaded")) and errs == 0
        res = r.get("resources") or []
        f = {(x.get("url", "")[:5], x.get("via")): x.get("ok") for x in res}
        return ok, (f"bravura={r.get('bravuraLoaded')} rendered={r.get('rendered')} jsErr={errs} "
                    f"fetchBravura={f.get(('font/', 'fetch'))} fetchSf2={f.get(('sound', 'fetch'))} "
                    f"xhrSf2={f.get(('sound', 'xhr'))} load->render={num(r.get('scoreLoadToRenderedMs'))}ms")
    if c == "messages":
        rt = r.get("roundTrip") or {}
        sq = rt.get("seq") or {}
        parts = [("rt", sq), ("js>dart", r.get("burstJsToDart") or {}), ("dart>js", r.get("burstDartToJs") or {})]
        ok = all(p.get("received") == 1000 and not p.get("missing") and not p.get("duplicates")
                 and not p.get("outOfOrder") for _, p in parts)
        rtt = rt.get("rttMs") or {}
        return ok, " ".join(f"{n}={p.get('received')}/{p.get('sent')}(m{p.get('missing')} d{p.get('duplicates')} o{p.get('outOfOrder')})"
                            for n, p in parts) + f" rtt med={num(rtt.get('median'), 2)} p99={num(rtt.get('p99'), 2)}ms jsErr={errs}"
    if c == "overlay":
        keys = [k for k in r if k.startswith("overlay") or k in ("covered", "flutterOverlay", "pointerBlocked")]
        return (r.get("ok") is True), " ".join(f"{k}={json.dumps(r[k])[:60]}" for k in keys[:4]) + f" jsErr={errs} ok={r.get('ok')}"
    if c.startswith("resize"):
        st = r.get("steps") or []
        inner = all(s.get("innerWidthMatches") for s in st)
        rep = all(s.get("repaintedAfterResize") for s in st[1:])
        rep0 = [bool(s.get("repaintedAfterResize")) for s in st]
        return (inner and rep and bool(st)), (f"inner={'/'.join(str(s.get('innerWidth')) for s in st)} match={inner} "
                                              f"repaint={rep0} rafFrames={num(r.get('rafLoopFrames'), 0)}")
    if c == "capture":
        m = r.get("msgLatencyMs") or {}
        sq = r.get("sequence") or {}
        return None, (f"rafFps={num(r.get('rafFps'))} flutterFps={num(r.get('flutterFps'), 2)} "
                      f"lat med={num(m.get('median'), 2)} p99={num(m.get('p99'), 2)} max={num(m.get('max'), 1)}ms n={m.get('n')} "
                      f"seq={sq.get('received')}/{sq.get('sent')} lost={sq.get('lost')} dup={sq.get('duplicated')}")
    if c.startswith("songsterr"):
        b = r.get("htmlBytes") or r.get("htmlBytesAfter4s") or r.get("htmlBytesAtFinish") or 0
        hid = f" pageReady={r.get('msToPageReady')}ms jsAlive={r.get('jsAlive')} ticks2s={r.get('jsTicksIn2s')}" if "msToPageReady" in r else ""
        return b > SONGSTERR_MIN_BYTES, (f"html={b}B mode={r.get('hiddenModeUsed')}{hid} tPage={num(r.get('secondsToPageFinished'))}s "
                                         f"tHtml={num(r.get('secondsToFirstHtml'))}s title={str(r.get('title'))[:30]!r} jsErr={errs}")
    if c.startswith("keys"):
        out = []
        for side in ("js", "flutter"):
            vd = verdict_bad((r.get("verdict") or {}).get(side))
            out.append(f"{side}: lost={vd[0] if vd else '?'} dup={vd[1] if vd else '?'}")
        fl = verdict_bad((r.get("verdict") or {}).get("flutter"))
        ok = None
        if c == "keys-flutter":
            ok = bool(fl) and not fl[0] and not fl[1] and r.get("storm") is False
        return ok, " ".join(out) + f" storm={r.get('storm')} fieldTextOk={r.get('fieldTextOk')} fieldText={r.get('fieldText')!r}"
    return None, ""


def main():
    d, app = sys.argv[1], sys.argv[2]
    suffix = sys.argv[3] if len(sys.argv) > 3 else ""
    print(f"{'caso':<20} {'':<5} resumen")
    for c in CASES:
        p = os.path.join(d, f"wv-{app}-{c}{suffix}.json")
        if not os.path.exists(p):
            continue
        try:
            r = json.load(open(p))
        except Exception as e:  # noqa: BLE001
            print(f"{c:<20} {'ERR':<5} informe ilegible: {e}")
            continue
        ok, txt = summarize(c, r)
        flag = "n/a" if ok is None else ("PASA" if ok else "NO")
        extra = f" | dpr={r.get('devicePixelRatio')} ready={r.get('timeToReadyMs')}ms udd={r.get('userDataDirApplied')}"
        st = r.get("startup") or {}
        extra += f" start(ctrl/page)={st.get('controllerCreated')}/{st.get('pageFinished')}"
        if r.get("timedOut") or r.get("error"):
            extra += f" timedOut={r.get('timedOut')} error={str(r.get('error'))[:80]}"
        print(f"{c:<20} {flag:<5} {txt}{extra}")


if __name__ == "__main__":
    main()
