# Demo World V2.3 - Configuration Parity Report

## Version canonica

- Version: `2.3`.
- Seed: `pachangas-iq-demo-world-v2-3-2026-27`.
- Fecha sintetica: `2027-03-18T18:00:00.000Z`.
- Hash publico: `9dca7d56ef77a17fbc3b625a89bfcd44096afa8e1a0420689531b6573b3bc170`.
- Hash de autoridad PostgreSQL:
  `9f016b51e530b01b71f770da7b586a78add043f5231a32793460163376eab3ff`.
- Migraciones simuladas: `158`.
- Escrituras remotas: `0`.
- Snapshots historicos V2.1 y V2.2: conservados sin reescritura.

## Configuracion representada

La Demo ejecuta RPC reales en PostgreSQL temporal y exporta dos RuleRevision:

| Propiedad | Revision 1 | Revision 2 |
| --- | --- | --- |
| Fuente | League Wizard V2 | Configuration Center V1 |
| Modo | sencillo | avanzado |
| Preset | F7 estandar | personalizado |
| Duracion | 70 minutos | 80 minutos |
| Puntuacion | 3/1/0 | 2/1/0 |
| No-show | 3-0 | 4-0 |
| Amarillas | threshold 3 | threshold 4 |
| BLUE | OFF | ON |
| Arbitro | opcional | obligatorio |
| Tarifa | negociable | fija privada |
| Estado | frozen | frozen |

El comparador identifica cambios en `match`, `scoring`, `incidents`,
`discipline` y `referees`. Health devuelve `complete`, cero errores y cero
warnings; superficies publicas, pagos, torneos y pairing manual/hibrido figuran
como globalmente apagados.

## Paridad de autoridad

- el documento humano coincide con los valores y checksum de cada revision;
- el partido consume la revision efectiva y no el ultimo borrador;
- R5 materializa `YELLOW`, `RED` y `BLUE` desde la revision avanzada;
- Assignments consume `REQUIRED`, tarifa fija privada y readiness obligatorio;
- standings no cambia por tarjetas;
- la tarifa fija no aparece en el bundle publico;
- no existen endpoints POST, PUT, PATCH o DELETE en la Demo;
- los cambios de perspectiva viven solo en `sessionStorage` y se reinician;
- Rating, Rewards, Conduct y Billing permanecen intactos.

## Datos publicos

| Entidad | Cantidad |
| --- | ---: |
| Competiciones | 1 |
| RuleRevisions | 2 |
| CanonicalMatches | 15 |
| Rondas | 5 |
| Equipos | 30 |
| Jugadores | 331 |
| Arbitros | 8 |

El chunk `configuration.json` se carga de forma diferida y usa el hash global
en la URL. V2.3 mantiene la estructura GET-only/read-only de Demo World V2.

## Producto

La pestaña Configuracion permite consultar:

- resumen del reglamento;
- sencillo frente a avanzado;
- disciplina;
- arbitros;
- comparador;
- health;
- capacidades futuras apagadas.

No existe una segunda UI de reglas: la Demo proyecta los mismos contratos y
campos que el producto, dentro del shell publico de Demo World.

## Regresiones

| Gate | Resultado |
| --- | --- |
| `demo-world:v2:simulate` | `PASS` |
| `demo-world:v2:verify` | `PASS`, snapshot identico |
| `test:demo-world:v2` | `13/13 PASS` |
| Remote writes | `0` |
| Hash determinista | `PASS` |
| V2.1/V2.2 inmutables | `PASS` |
| Tarifa privada ausente | `PASS` |
| PWA cache versionada | `PASS` |

## QA visual

Configuration Parity, comparador y health se revisaron en desktop, portrait,
game landscape y PWA standalone:

- overflow raiz: 0;
- imagenes rotas: 0;
- navegacion duplicada: 0;
- errores de consola: 0;
- controles esenciales cortados: 0.

Android fisico, iPhone fisico y una instalacion fisica no se presentan como
PASS; no forman parte de la certificacion automatizada local.

## Limites

- Public competition surfaces: OFF.
- Payments: OFF.
- Tournament Engine: no iniciado.
- Manual/Hybrid Pairing: no implementado.
- Canonical legacy backfill: no ejecutado.
