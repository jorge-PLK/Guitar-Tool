# Fase 5 · Tablatura (parte de RF2, RF11)

- [x] Transcribir las guitarras con Basic Pitch y asignar cuerdas y trastes; transcribir también el bajo (4 cuerdas) y la batería (modelo aparte: bombo, caja y charles como mínimo). *Hecho y probado: `TabFingeringTests`, `TabQuantizeTests`, `TabTempoDriftTests`, `TabGridTests`, `DrumTranscriberTests` (T1: 1117/1117 golpes). Calidad según Jorge: bajo muy bueno, batería buena (platos confundidos con charles), guitarras pésimas (ADR-016; Fase 5b).*
- [x] Tablatura con alphaTab, cursor, edición y exportación a un único archivo de Guitar Pro con guitarras, bajo y batería, comprobado en Guitar Pro. *Hecho: `AlphaTabScoreTests`, `TabEditorTests`, `TabSynthTests`, `TabFingerprintTests`, `TabSourcesTests`, capturas de la pantalla y apertura en Guitar Pro 8 por Jorge. Falta que Jorge pruebe a fondo el teclado de edición y «Oír transcripción» con reproducción real.*

Condición de paso: tablatura de un tema con guitarras, bajo y batería exportada y abierta en Guitar Pro. Cumplida el 16/11/2026: «El roce de tu cuerpo» (Platero y Tú), 5 pistas y 181 compases, exportada con `--tab-export` y abierta en Guitar Pro 8 por Jorge; la batería suena con RSE.

Notas de cierre (ADR-016): la calidad de las guitarras no es aceptable y pasa a la Fase 5b; los compases irregulares (3/4, 2/4) en intros vienen del `BeatGrid`.
