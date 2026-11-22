import json, os, sys
d = sys.argv[1]
combos = ["via1-port", "via1-listener", "via2-port", "via2-listener", "none-port", "none-listener"]


def g(r, *k):
    for x in k:
        r = r.get(x) if isinstance(r, dict) else None
    return r


if len(sys.argv) > 2 and sys.argv[2] == "diag":
    loads = {}
    for lf in os.listdir(d):
        if lf.startswith("diag-load"):
            for ln in open(os.path.join(d, lf)):
                t = ln.split()
                if len(t) == 2:
                    loads[t[0]] = t[1]
    print("run | cpu% | code | thOk | calls/err | rt med/p99/max | wdExclBusy | wd glob(fase) | shut,clean | 60f/60b p99 us | burst us | lost/ooo | rss | failed")
    for f in sorted(x for x in os.listdir(d) if x.startswith("diag-") and x.endswith(".json")):
        tag = f[:-5]
        r = json.load(open(os.path.join(d, f)))
        try:
            code = open(os.path.join(d, tag + ".code")).read().strip()
        except OSError:
            code = ""
        rt = g(r, "c_roundtrip", "first4000_ms") or {}
        e = g(r, "e_nativeToDart") or {}
        pk = r.get("watchdogPeaks") or []
        gl = "%s(%s)" % (r.get("watchdogGlobalMaxMs"), pk[0]["phase"] if pk else "-")
        lost = sum(e.get(k, {}).get("lost", 0) for k in ("free_60hz", "busy_60hz", "burst_5000"))
        ooo = sum(e.get(k, {}).get("outOfOrder", 0) for k in ("free_60hz", "busy_60hz", "burst_5000"))
        rss = g(r, "c_roundtrip", "rssMb") or {}
        print("%s | %s | %s | %s | %s/%s | %s/%s/%s | %s | %s | %s,%s | %s/%s | %s | %s/%s | %s>%s | %s" % (
            tag, loads.get(tag), code, g(r, "threads", "threadsOk"), rt.get("n"), g(r, "c_roundtrip", "errors"),
            rt.get("median"), rt.get("p99"), rt.get("max"), r.get("watchdogMaxExclBusy"), gl,
            g(r, "h_shutdown", "ms"), g(r, "h_shutdown", "payload", "clean"),
            g(e, "free_60hz", "latencyUs", "p99"), g(e, "busy_60hz", "latencyUs", "p99"),
            g(e, "burst_5000", "usPerMessage"), lost, ooo, rss.get("before"), rss.get("after8000"), r.get("failed")))
        print("   picos: " + "; ".join("%sms %s @%s" % (p["ms"], p["phase"], p["tMs"]) for p in pk[:3]))
    sys.exit(0)

print("combo | code | thOk | calls/err | rt med/p99/max ms | wd max ms | shut ms,clean | 60f p99 / 60b p99 us | burst us/msg | lost/ooo | rss | bg ev")
for c in combos:
    code = ""
    try:
        code = open(os.path.join(d, "p2-%s.code" % c)).read().strip()
    except OSError:
        pass
    p = os.path.join(d, "p2-%s.json" % c)
    if not os.path.exists(p):
        print("%s | %s | SIN INFORME" % (c, code))
        continue
    r = json.load(open(p))
    rt = g(r, "c_roundtrip", "first4000_ms") or {}
    e = g(r, "e_nativeToDart") or {}
    wd = max([x for x in (g(r, "d_uiBlock", "watchdogMaxDelayMs"), e.get("watchdogMaxDelayMs"),
                          g(r, "h_shutdown", "watchdogMaxDelayMs")) if x is not None] or [None])
    lost = sum(e.get(k, {}).get("lost", 0) for k in ("free_60hz", "busy_60hz", "burst_5000"))
    ooo = sum(e.get(k, {}).get("outOfOrder", 0) for k in ("free_60hz", "busy_60hz", "burst_5000"))
    rss = g(r, "c_roundtrip", "rssMb") or {}
    bg = g(r, "g_background") or {}
    print("%s | %s | %s | %s/%s | %s/%s/%s | %s | %s,%s | %s / %s | %s | %s/%s | %s>%s | %s+%s" % (
        c, code, g(r, "threads", "threadsOk"), rt.get("n"), g(r, "c_roundtrip", "errors"),
        rt.get("median"), rt.get("p99"), rt.get("max"), wd,
        g(r, "h_shutdown", "ms"), g(r, "h_shutdown", "payload", "clean"),
        g(e, "free_60hz", "latencyUs", "p99"), g(e, "busy_60hz", "latencyUs", "p99"),
        g(e, "burst_5000", "usPerMessage"), lost, ooo, rss.get("before"), rss.get("after8000"),
        bg.get("jobsProgressEvents"), bg.get("libraryChangedEvents")))
    print("   threads:", json.dumps(r.get("threads")), "failed:", r.get("failed"))
