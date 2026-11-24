# Worktrees para las olas 1, 2 y 3 en paralelo

Una sesión de Claude por ola, cada una en su worktree junto al repo. Todas integran en `fase-7f`.

## 1. Crear el worktree

```sh
cd "/Volumes/SSD Mac/Personales/Guitar Tool"
git fetch origin
git worktree add "../Guitar Tool-ola1" -b ola1-local origin/fase-7f
cd "../Guitar Tool-ola1"
git branch --set-upstream-to=origin/fase-7f
```

Repite con `ola2` y `ola3`. Abre la sesión de Claude con ese directorio como raíz.

## 2. Ciclo por parte integrada

1. `git pull --rebase`
2. Commit (el commit-gate lee `Temp/last-run.txt` del propio worktree: hace falta una pasada completa de `Tools/test.sh` en verde).
3. `git push origin HEAD:fase-7f`

Nunca se fuerza el push ni se empuja a `main`. Si el push se rechaza: `git pull --rebase` y repetir.

## 3. Enlaces simbólicos

Nada de `Vendor/` está versionado (24/11/2026: solo `helpers/` y `win/`, ignorados), así que se enlaza entero:

```sh
R="/Volumes/SSD Mac/Personales/Guitar Tool"
ln -s "$R/Vendor" Vendor
mkdir -p Temp/flutter
cp -R "$R/Temp/flutter/ref-projects" Temp/flutter/ref-projects
```

- `Temp/` está en `.gitignore` y es propio de cada worktree: logs en `Temp/logs/` y `Temp/last-run.txt` del gate (el hook se ejecuta en el worktree donde se hace el commit).
- `Tools/flutter/run.sh` usa `Temp/flutter/ref-projects` y `Temp/flutter/support` relativos a la raíz del worktree. Nunca apuntes a la carpeta real de proyectos.
- `ref-projects` se copia, no se enlaza: la app escribe en los proyectos y cada worktree debe tener los suyos.

## 4. Qué se recompila por worktree

- `Packages/*/.build` (ignorado por `.build/`): primera pasada de `Tools/test.sh` larga.
- `FlutterApp/build` (ignorado por `FlutterApp/.gitignore`).
- El dylib: `Tools/flutter/build-core.sh`. Calcula la raíz desde su propia ruta y lo copia y firma dentro de `FlutterApp/build/macos/.../toneforge.app/Contents/Frameworks/`; si aún no hay `.app`, avisa y no lo copia. Ejecútalo tras cada `flutter build`.
- FVM: la versión la fija `.fvmrc` en la raíz (versionado). Si `fvm flutter` falla en el worktree, ejecuta `fvm install` dentro de `FlutterApp/`.

## 5. Zonas compartidas

- ARB (`FlutterApp/lib/l10n/app_es.arb`, `app_en.arb`): por bloques con un ancla por área. Añade claves solo debajo del ancla de tu área.
- Fixtures de contrato: un fichero por área, `Packages/AppCore/Tests/AppCoreTests/ContractFixtures+<Área>.swift`, con `FixtureRig` interno; datos en `Contract/fixtures/<área>/`.
- Código de pantalla: solo en `FlutterApp/lib/features/<área>/`.
- Congelados fuera de la ola 0: kit (`lib/widgets`), `core/` y `theme/`. Si falta algo, se pide al orquestador; no se toca.
- Ajustes: cada ola crea su propio fichero de pestaña; no se edita el de otra.

## 6. Cerrar la ola

Con todo integrado y empujado:

```sh
cd "/Volumes/SSD Mac/Personales/Guitar Tool"
git worktree remove "../Guitar Tool-ola1"
git branch -d ola1-local
```

`git worktree remove` falla si hay cambios sin guardar; no uses `--force` sin revisar.
