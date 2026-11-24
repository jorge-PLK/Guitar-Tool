#!/bin/bash
# Build + tests de ToneForge con salida resumida (los logs completos van a Temp/logs/).
#
#   Tools/test.sh                     todos los paquetes de Packages/ + build de la app
#                                     → escribe Temp/last-run.txt (lo lee .claude/hooks/commit-gate.sh)
#   Tools/test.sh <Paquete> [Filtro]  un paquete, opcionalmente con `swift test --filter <Filtro>`
#                                     → no escribe last-run.txt
#   Tools/test.sh App                 solo el build de la app, sin tests → no escribe last-run.txt
#   Tools/test.sh FlutterApp [Filtro] FlutterApp/: `flutter analyze` + `flutter test`
#                                     Filtro = ruta existente bajo FlutterApp/ (p. ej. test/widgets/k1 o un
#                                     fichero .dart) → objetivo de `flutter test`; si no, `--name <Filtro>`
#                                     (regex sobre el nombre completo, group incluido).
#                                     Con filtro los logs son Temp/logs/FlutterApp-<filtro>-<pid>.{log,json,err}
#                                     (no se pisan entre agentes). Sin filtro: FlutterApp.{log,json,err}.
#                                     → no escribe last-run.txt (en el run completo va al final)
#   TF_UPDATE_GOLDENS=1 Tools/test.sh FlutterApp <Filtro>
#                                     añade `--update-goldens` (solo con filtro; se ignora sin él)
#
# Salida: 0 verde, 1 tests fallidos, 2 errores de compilación o nada que probar.
# La app se compila (no se testea): la lógica y sus tests viven en los paquetes.
# Esquema de la app: TF_SCHEME (por defecto ToneForge).
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
mkdir -p Temp/logs

full=1
app_only=0
flutter_only=0
pkgs=()
filter=""
if [ "${1:-}" = "App" ]; then
  full=0
  app_only=1
elif [ "${1:-}" = "FlutterApp" ]; then
  full=0
  flutter_only=1
  filter="${2:-}"
elif [ $# -ge 1 ]; then
  full=0
  pkgs=("$1")
  filter="${2:-}"
  [ -f "Packages/$1/Package.swift" ] || { echo "No existe Packages/$1/Package.swift"; exit 2; }
else
  for p in Packages/*/Package.swift; do
    [ -f "$p" ] || continue
    d="${p%/Package.swift}"
    pkgs+=("${d#Packages/}")
  done
fi

# Turno del Mac: un solo run pesado a la vez entre el repo y todos sus worktrees (olas en
# paralelo), por orden de llegada. Cada run saca número (contador en el .git común), espera a
# ser el primero vivo de la cola y entonces coge el cerrojo `lockf`. Los números de procesos
# muertos se limpian solos. Libres: `FlutterApp <Filtro>` y TF_TEST_FORCE=1 (pasadas cortas de
# un paquete; no vale para la suite entera). TF_TEST_NOLOCK=1: sin turno (solo con Jorge).
# TF_TEST_LOCKDIR=<dir>: otra cola (pruebas del propio script).
if [ -n "${TF_TEST_FORCE:-}" ] && [ "$full" -eq 1 ]; then
  echo "test.sh: TF_TEST_FORCE no vale para la suite entera; hace cola."
  unset TF_TEST_FORCE
fi
if [ -z "${TF_TEST_LOCKED:-}" ] && [ -z "${TF_TEST_NOLOCK:-}" ] && [ -z "${TF_TEST_FORCE:-}" ] \
   && ! { [ "$flutter_only" -eq 1 ] && [ -n "$filter" ]; }; then
  lockdir="${TF_TEST_LOCKDIR:-}"
  if [ -z "$lockdir" ]; then
    common="$(git rev-parse --git-common-dir 2>/dev/null)" && lockdir="$(cd "$common" && pwd)"
  fi
  if [ -n "$lockdir" ]; then
    lock="$lockdir/toneforge-test.lock"
    queue="$lockdir/toneforge-test.queue"
    mkdir -p "$queue"
    n=$(/usr/bin/lockf -k "$queue/.counter.lock" /bin/bash -c \
      'c=$(cat "$1/.counter" 2>/dev/null || echo 0); c=$((c+1)); echo "$c" > "$1/.counter"; echo "$c"' \
      _ "$queue")
    ticket="$queue/$(printf '%08d' "$n").$$"
    echo "$root · ${*:-entero} · pedido $(date '+%H:%M:%S')" > "$ticket"
    trap 'rm -f "$ticket"; exit 130' INT TERM HUP
    said=""
    while :; do
      ahead=0
      first=""
      for t in $(ls "$queue" | sort); do
        if ! kill -0 "${t##*.}" 2>/dev/null; then rm -f "$queue/$t"; continue; fi
        [ "$t" = "${ticket##*/}" ] && break
        ahead=$((ahead + 1))
        [ -z "$first" ] && first="$t"
      done
      [ "$ahead" -eq 0 ] && break
      if [ "$ahead" != "$said" ]; then
        echo "test.sh: turno $n, $ahead delante (siguiente: $(cat "$queue/$first" 2>/dev/null || echo '?'))"
        said="$ahead"
      fi
      sleep 3
    done
    trap - INT TERM HUP
    if ! /usr/bin/lockf -k -s -t 0 "$lock" true; then
      echo "test.sh: turno $n, el primero; esperando a que acabe: $(cat "$lock.owner" 2>/dev/null || echo '?')"
    fi
    export TF_TEST_LOCKED=1
    # Mismo PID tras exec: el número sigue «vivo» mientras espera el cerrojo; se borra al cogerlo.
    exec /usr/bin/lockf -k "$lock" /bin/bash -c \
      'rm -f "$4"; echo "$1 · $2 · $(date "+%H:%M:%S")" > "$3.owner"; shift 4; exec "$@"' \
      _ "$root" "${*:-entero}" "$lock" "$ticket" "$root/Tools/test.sh" "$@"
  fi
fi

summary=()
status=0   # 0 verde, 1 fallos, 2 compilación
bump() { [ "$1" -gt "$status" ] && status=$1; }

[ "$full" -eq 1 ] && echo "RUNNING $(date '+%Y-%m-%d %H:%M:%S')" > Temp/last-run.txt

# Errores de compilación (no los fallos de XCTest, que también llevan "error: -[").
compile_errors() { grep -aE ': error: ' "$1" | grep -avE 'error: -\[' | sort -u | head -15; }

for pkg in ${pkgs[@]+"${pkgs[@]}"}; do   # bash 3.2 + set -u: array vacío
  log="Temp/logs/$pkg.log"
  args=(test --package-path "Packages/$pkg")
  [ -n "$filter" ] && args+=(--filter "$filter")
  swift "${args[@]}" > "$log" 2>&1
  rc=$?

  xct=$(grep -aE 'Executed [0-9]+ tests?' "$log" | tail -1 | sed -E 's/^[[:space:]]+//')
  st=$(grep -aE 'Test run with [0-9]+ tests?' "$log" | grep -av 'with 0 tests' | tail -1 | sed -E 's/^[^T]*//')
  totals="${xct}${xct:+${st:+ · }}${st}"

  if [ "$rc" -eq 0 ]; then
    summary+=("OK    $pkg: ${totals:-sin tests}")
  elif [ -n "$totals" ]; then
    bump 1
    summary+=("FALLO $pkg: $totals")
    while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done < <(
      grep -aE 'error: -\[|✘ Test .*(failed|recorded an issue)' "$log" | sed -E "s#^$root/##" | sort -u | head -15)
  else
    bump 2
    summary+=("COMPILACIÓN $pkg (rc $rc)")
    errs=$(compile_errors "$log" | sed -E "s#^$root/##")
    [ -z "$errs" ] && errs=$(tail -5 "$log")
    while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done <<< "$errs"
  fi
done

# Paso FlutterApp: analyze + test (subshell: no cambia el cwd global). Sale 0 verde, 1 fallos o avisos, 2 compilación.
flutter_step() {
  local base="Temp/logs/FlutterApp"
  local targs=(test --reporter=json)
  if [ -n "$filter" ]; then
    local safe
    safe=$(printf '%s' "$filter" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-60)
    base="Temp/logs/FlutterApp-$safe-$$"
    if [ -e "FlutterApp/$filter" ]; then
      targs+=("$filter")
    else
      targs+=(--name "$filter")
    fi
    [ "${TF_UPDATE_GOLDENS:-0}" = "1" ] && targs+=(--update-goldens)
  fi
  local log="$base.log" json="$base.json" err="$base.err"
  (
    cd "$root/FlutterApp" || exit 2
    { echo "== flutter analyze"; fvm flutter analyze; echo "analyze-exit=$?"; } > "$root/$log" 2>&1
    fvm flutter "${targs[@]}" > "$root/$json" 2> "$root/$err"
  )
  { echo "== flutter test (json en $json)"; cat "$err"; } >> "$log"
  local out rc
  out=$(python3 -I - "$log" "$json" <<'PY'
import json, re, sys
log, jpath = sys.argv[1:3]
issues = []
for l in open(log, errors="replace"):
    if l.startswith("== flutter test"):
        break
    m = re.match(r"\s+(info|warning|error) • (.*) • (\S+?:\d+):\d+ • ", l)
    if m:
        issues.append(f"analyze {m[1]} {m[3]}: {m[2]}")
names, lines = {}, {}
passed = failed = skipped = 0
loadfail, fails = [], []
try:
    raw_lines = open(jpath, errors="replace").read().splitlines()
except OSError:
    raw_lines = []
for raw in raw_lines:
    try:
        e = json.loads(raw)
    except ValueError:
        continue
    t = e.get("type")
    if t == "testStart":
        n = e["test"]
        names[n["id"]] = n["name"]
        lines[n["id"]] = (n.get("url") or "", n.get("line"))
    elif t == "error":
        tid = e["testID"]
        msg = " ".join(str(e["error"]).split())[:110]
        m = re.search(r"^(test/\S+?\.dart|integration_test/\S+?\.dart)[: ](\d+):\d+", e.get("stackTrace", ""), re.M)
        if m:
            loc = f"{m[1]}:{m[2]}"
        else:
            u, ln = lines.get(tid, ("", None))
            loc = f"{u.split('/')[-1]}:{ln}"
        if names.get(tid, "").startswith("loading "):
            loadfail.append(f"{names[tid][8:].split('/test/')[-1]}: {msg}")
        else:
            fails.append(f"{loc} {msg}")
    elif t == "testDone" and not e.get("hidden"):
        if e.get("skipped"):
            skipped += 1
        elif e["result"] == "success":
            passed += 1
        else:
            failed += 1
total = passed + failed + skipped
code = 0
if loadfail or (total == 0 and not fails):
    code = 2
elif failed or issues:
    code = 1
head = f"analyze {len(issues)} avisos · tests {passed} pasados, {failed} fallados, {skipped} saltados"
rest = issues[:8]
rest += [f"COMPILACIÓN {x}" for x in loadfail[:5]]
if total == 0 and not loadfail and not fails:
    rest.append("no hay tests que ejecutar")
rest += [f"{x}" for x in fails[:10]]
print(head)
for r in rest:
    print(r)
sys.exit(code)
PY
)
  rc=$?
  local first rest
  first=$(printf '%s\n' "$out" | head -1)
  rest=$(printf '%s\n' "$out" | tail -n +2)
  case "$rc" in
    0) summary+=("OK    FlutterApp: $first") ;;
    1) bump 1; summary+=("FALLO FlutterApp: $first") ;;
    *) bump 2; summary+=("COMPILACIÓN FlutterApp (rc $rc): $first") ;;
  esac
  while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done <<< "$rest"
  flutter_ran=1
}

flutter_ran=0
app_built=0
if [ "$full" -eq 1 ] || [ "$app_only" -eq 1 ]; then
  for proj in App/*.xcodeproj; do
    [ -d "$proj" ] || continue
    log="Temp/logs/App.log"
    xcodebuild -project "$proj" -scheme "${TF_SCHEME:-ToneForge}" -destination 'platform=macOS' \
      -derivedDataPath Temp/DerivedData -quiet build > "$log" 2>&1
    rc=$?
    app_built=1
    if [ "$rc" -eq 0 ]; then
      summary+=("OK    App: build")
    else
      bump 2
      summary+=("COMPILACIÓN App (rc $rc)")
      errs=$(compile_errors "$log" | sed -E "s#^$root/##")
      [ -z "$errs" ] && errs=$(tail -5 "$log")
      while IFS= read -r l; do [ -n "$l" ] && summary+=("      $l"); done <<< "$errs"
    fi
    break
  done
fi

if [ "$flutter_only" -eq 1 ] || { [ "$full" -eq 1 ] && [ -f FlutterApp/pubspec.yaml ]; }; then
  flutter_step
fi

if [ "${#pkgs[@]}" -eq 0 ] && [ "$app_built" -eq 0 ] && [ "$flutter_ran" -eq 0 ]; then
  echo "Nada que probar: no hay Packages/*/Package.swift, App/*.xcodeproj ni FlutterApp/pubspec.yaml."
  [ "$full" -eq 1 ] && echo "DONE Empty" > Temp/last-run.txt
  exit 2
fi

case "$status" in
  0) head="DONE Passed" ;;
  1) head="DONE Failed" ;;
  *) head="DONE CompileError" ;;
esac

{
  echo "$head $(date '+%Y-%m-%d %H:%M:%S')${filter:+ (filtro: $filter)}"
  printf '%s\n' "${summary[@]}"
} | tee Temp/last-print.txt

if [ "$full" -eq 1 ]; then
  cp Temp/last-print.txt Temp/last-run.txt
fi
rm -f Temp/last-print.txt
exit "$status"
