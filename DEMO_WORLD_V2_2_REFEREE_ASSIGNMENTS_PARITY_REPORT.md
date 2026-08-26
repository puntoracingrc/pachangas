# Demo World V2.2 - Referee Assignments Parity

## Version canonica

- Version: `2.2`.
- Seed: `pachangas-iq-demo-world-v2-2-2026-27`.
- Fecha sintetica: `2027-03-18T18:00:00.000Z`.
- Hash publico: `58074f1cf5892f5730fee4e3af4d62b44f8d551ee4f21f9ec07acebb46a65697`.
- Hash de autoridad PostgreSQL: `a11f5226f9f56ae3b60d0fc418128e3b9c3ab61393f7cd74a2261306174504be`.
- Migraciones simuladas: 152.
- Escrituras remotas: 0.
- Snapshot historico V2.1: conservado sin reescritura en
  `public/demo-world/v2-1/`.

## Mundo arbitral

| Hecho | Evidencia |
| --- | ---: |
| RefereeProfiles | 8 |
| CanonicalMatches de Liga | 15 |
| Assignments historicas | 16 |
| Completadas | 13 |
| Rechazadas | 1 |
| Canceladas por conflicto | 1 |
| Reemplazadas | 1 |
| Partidos sin arbitro | 2 |
| Reconfirmaciones de horario | 2 |
| Solapamientos activos | 0 |
| Maximo MAIN por partido | 1 |
| Eventos R5 en partidos arbitrados | 18 |
| Eventos R5 ligados a Assignment | 18 |
| Eventos R5 sin lineage | 0 |

El escenario incluye un conflicto horario rechazado por la autoridad, un
reemplazo con lineage completo, un aplazamiento R4D con horario original y
efectivo, reconfirmacion real y reconstruccion convergente de estadisticas.

## Terminos y privacidad

La Demo cubre `FIXED`, `NEGOTIABLE` y `VOLUNTEER`. No simula pagos: todos los
read models declaran `paymentManagedByPachangasIq=false`. Los terminos privados,
counter, identidad Auth, PII y evidencias administrativas quedan fuera del
snapshot publico.

## Paridad de producto

Demo World reutiliza los renderers de producto para:

- mercado de arbitros;
- perfil arbitral;
- asignaciones y Mis partidos arbitrados;
- mesa del organizador;
- arbitro del partido;
- conflicto, reemplazo y reconfirmacion;
- contadores disciplinarios y estadisticas reconstruibles.

No existe una `DemoRefereeAssignment` paralela. El snapshot deriva de las RPC
R1, R3, R4A, R4B, R4C, R4D y R5 ejecutadas en PostgreSQL temporal.

## Regresiones

- `npm run demo-world:v2:simulate`: PASS.
- `npm run demo-world:v2:verify`: PASS.
- `npm run test:demo-world:v2`: PASS, 12/12.
- Determinismo: PASS para seed, autoridad y chunks publicos.
- Rating, Rewards y Conduct: intactos.
- `remoteWrites`: 0.
- Service Worker: precachea V2.2 y sus chunks versionados.

## QA visual

Se comprobaron Inicio Demo, Arbitros, propuestas, confirmadas, Mercado y mesa
del organizador en `1440x900`, `390x844` y `844x390`:

- overflow horizontal: 0;
- imagenes rotas: 0;
- controles sticky/fixed fuera del viewport: 0;
- errores de runtime en contexto limpio: 0;
- submenu activo visible en portrait y landscape;
- la fixture de Assignment abre directamente su estado funcional.

La PWA del build de produccion registra y controla `sw.js`, mantiene la lectura
V2.2 con la red cortada y converge al reconectar. Android, iPhone y una
instalacion fisica siguen `PENDING`; no se presentan como `PASS`.

## Limites

- Payments: OFF.
- Disciplina publica: OFF.
- Tournament Engine: no iniciado.
- Canonical legacy backfill: no ejecutado.
- La Demo es read-only y solo permite estado efimero en `sessionStorage`.
