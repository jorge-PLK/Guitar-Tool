#!/bin/bash
# P9 prueba 3 (fotogramas), lado nativo. De momento solo construye dylib, humo y app macOS.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
P9="$ROOT/Probes/P9-flutter"
LOGS="$ROOT/Temp/logs"
mkdir -p "$LOGS"
swift build --package-path "$P9/AppCoreFFI" -c release >"$LOGS/p9-p3-swift.log" 2>&1 || { echo "swift build falló: $LOGS/p9-p3-swift.log"; exit 1; }
(cd "$P9/app" && fvm flutter build macos --release >"$LOGS/p9-p3-flutter.log" 2>&1) || { echo "flutter build falló: $LOGS/p9-p3-flutter.log"; exit 1; }
echo "build ok"
