# Fase 4 · Guitarras y secciones (RF6, parte de RF5)

- [x] Separar la pista de guitarras en A y B por panorama estéreo. *Cambió (ADR-014): la panorámica con máscaras se descartó; «Guitarras en L y R» usa los canales L y R, y los tramos de solo usan el modelo lead/rhythm.*
- [x] Clasificar pasajes en rítmica o solista con Basic Pitch. *Cambió (ADR-014): Basic Pitch y `PassageClassifier` hechos, pero la clasificación automática queda fuera de la cola; el solo es una sección marcada a mano.*
- [x] Nombrar las guitarras, marcar o corregir secciones a mano y mostrar la confianza
- [x] Añadir las guitarras separadas al mezclador de la Fase 2
- [x] Probar modelos dedicados a guitarra frente a BS-RoFormer SW (8,23 / 11,03 / 4,38 dB): probado, descartado (Mega 53: 7,58 dB; becruily: 5,81 dB en T1). Decidido por Jorge en la Fase 0.

Condición de paso: Robe y Uoho en pistas distintas en 3 temas de prueba. Cumplida el 16/11/2026 (3 temas de Extremoduro con «Guitarras en L y R», de oído por Jorge).

Notas de cierre (ADR-014): Backing va sin grabación ni A/B (el código de la Fase 3 se conserva para la Fase 6) y la Etapa 2 sale de la UI («Igualar tono», «Pedalera y TONE3000», rigs en Biblioteca). Un modelo solista frente a rítmica de mejor calidad queda para la Etapa 2.
