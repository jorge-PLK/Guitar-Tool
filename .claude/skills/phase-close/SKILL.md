---
name: phase-close
description: Cierra una fase de ToneForge — suite completa, condición de paso, CODEMAP, plan, spec con lo aprendido, ADR y commit. Solo la invoca Jorge con /phase-close.
disable-model-invocation: true
argument-hint: "[Fase N | P<n>]"
---

# Cerrar fase

Argumento: `$ARGUMENTS` (p. ej. `Fase 1`, o `P2` para cerrar una prueba suelta de la Fase 0). Sin argumento, dedúcelo de la rama (`git branch --show-current`, `fase-N`) y del último ADR (`docs/DECISIONS.md`, al final), y dilo antes de seguir.

Para en cuanto un paso falle y di qué falta. No marques nada que no hayas comprobado.

## 1. Qué entra

- `git status --short` y `git diff --stat main`. Separa lo que es de la fase de lo ajeno (ficheros de usuario de Xcode, `.DS_Store`, salidas de `Probes/*/out/`). Lo ajeno no entra; si dudas, pregunta.
- Ficheros nuevos, renombrados o borrados: `git diff --name-status main` + `git ls-files --others --exclude-standard`.

## 2. Tests: la suite entera

Lanza `tf-qa` con "suite entera y build de la app". Tiene que volver `VEREDICTO: ok` y `Temp/last-run.txt` empezar por `DONE Passed`. Apunta los totales. Si algo falla: para y enseña los fallos. El hook `commit-gate` bloquea el commit de todos modos.

En la Fase 0 no hay suite: comprueba en su lugar que cada prueba cerrada tiene su `docs/probes/P<n>-*.md` con resultado medido.

## 3. Condición de paso

Lee en `docs/plan/fase-N.md` la condición de paso de la fase. Si se demuestra con un test, nómbralo. Si pide hardware u oído (audio por USB, latencia con la Flex Prime, "suena reconocible", separación A/B que convence), **pregúntaselo a Jorge**: sin su confirmación, la fase no se cierra.

## 4. Docs (por `tf-docs`, con la lista del paso 1 y los informes de la fase)

- CODEMAP: filas en `docs/codemap/<Kit>.md` para cada `.swift` nuevo o renombrado con su API pública, cada recurso (modelos, audios de prueba) y cada script de `Probes/`; paquete nuevo = fichero nuevo + línea en la lista de `docs/CODEMAP.md`. Que no quede la entrada de lo borrado. Línea *Última actualización* en la línea 3 de `docs/CODEMAP.md`.
- `docs/plan/fase-N.md`: `[x]` solo lo demostrado (test nombrado en cursiva) o confirmado por Jorge; lo demás `[ ]` con nota de lo que falta. Fase nueva = fichero nuevo + línea en la lista de `docs/plan.md`.
- Spec: lo aprendido en la fase, en `docs/spec.md` (núcleo) o en `docs/spec/fase-N.md` (el plan lo pide: «la spec queda actualizada con lo aprendido»). Mini-spec nueva = fichero nuevo + encabezado con enlace en `docs/spec.md`.
- ADR de cierre `docs/adr/ADR-NNN.md` (formato de los anteriores: `# ADR-NNN · AAAA-MM-DD · Título (Fase N)`, viñetas en negrita, **Tests**, **Pendiente de Jorge**, **Estado**) y su línea en `docs/DECISIONS.md`. Toda referencia `ADR-NNN` nueva apunta a un ADR que existe.
- "Estado actual" de `CLAUDE.md`, máximo 3 líneas.

## 5. Commit

- Haz el commit directamente, sin pedir confirmación a Jorge (lo pidió el 15/11/2026); enseña después el hash y la lista de ficheros.
- Mensaje en inglés, imperativo, con el estilo de `git log -5 --format='%s%n%b'` (p. ej. `Close Phase 1: library and stem separation (ADR-004)`).
- **Sin** trailer `Co-Authored-By`.
- En la rama `fase-N`. `git add` con rutas explícitas, nunca `git add -A`. Sin push ni merge a `main`: eso lo decide Jorge.
