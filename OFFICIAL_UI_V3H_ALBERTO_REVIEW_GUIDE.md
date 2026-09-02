# Official UI V3H Alberto Review Guide

Duración estimada: 10–15 minutos. Esta revisión es posterior al deployment; no bloquea la publicación.

## Recorrido de 10 minutos

1. [Landing](https://pachangasiq.com/) — comprueba si entiendes en cinco segundos qué ofrece la app.
2. [Revisión rápida](https://pachangasiq.com/demo?review=1) — completa `Usuario nuevo`.
3. [Demo jugador](https://pachangasiq.com/demo?tab=inicio&perspective=player) — abre el próximo partido.
4. [Demo owner](https://pachangasiq.com/demo?tab=inicio&perspective=admin) — revisa la acción principal.
5. [Partidos](https://pachangasiq.com/demo?tab=partido&perspective=player) — revisa próximo, alineación y resultado.
6. [Retos](https://pachangasiq.com/demo?tab=retos&perspective=admin) — cambia Activos/Historial y el filtro.
7. [Mercado](https://pachangasiq.com/demo?tab=mercado&perspective=admin) — busca un partido, jugador y rival.
8. [Equipo](https://pachangasiq.com/demo?tab=equipo&perspective=admin) — revisa portada y plantilla.
9. [Avisos](https://pachangasiq.com/demo?tab=avisos&perspective=player) — abre y resuelve una acción local.

La etiqueta `SIMULACIÓN` debe permanecer visible. Ninguna acción de este recorrido escribe remotamente ni notifica personas.

## Contact sheets

- [Desktop](docs/official-ui-v3h/V3H_SOCIAL_CORE_DESKTOP_CONTACT_SHEET.png)
- [Portrait](docs/official-ui-v3h/V3H_SOCIAL_CORE_PORTRAIT_CONTACT_SHEET.png)
- [Landscape](docs/official-ui-v3h/V3H_SOCIAL_CORE_LANDSCAPE_CONTACT_SHEET.png)
- [Estados vacíos](docs/official-ui-v3h/V3H_EMPTY_STATES_CONTACT_SHEET.png)
- [Recorridos E2E](docs/official-ui-v3h/V3H_END_TO_END_JOURNEYS_CONTACT_SHEET.png)
- [Antes y después](docs/official-ui-v3h/V3H_BEFORE_AFTER_CONTACT_SHEET.png)

## Preguntas humanas

- ¿Entiendes dónde estás?
- ¿Ves qué debes pulsar?
- ¿Hay demasiado texto?
- ¿Algo parece técnico?
- ¿Algún botón compite con otro?
- ¿La pantalla parece una app deportiva sencilla?
- ¿El landscape sigue pareciendo un videojuego?

## Comprobación rápida por dispositivo

- Portrait: título, contexto y acción principal caben sin quedar detrás de la navegación.
- Landscape: no hay footer, controles cortados ni scroll horizontal raíz.
- Giro: conserva tab, perspectiva y recorrido.
- Teclado: no tapa Guardar ni la acción principal.
- PWA: la navegación y la safe area se mantienen.

## QA física pendiente

- Android físico: PENDING.
- iPhone físico: PENDING.
- PWA instalada físicamente: PENDING.

No deben interpretarse como PASS hasta probar dispositivos reales.
